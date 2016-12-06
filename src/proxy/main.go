/*

main.go

This is a simple caching proxy. This is designed for the Dreamwidth project to
allow us to proxy HTTP embedded content.

Authors:
     Mark Smith <mark@dreamwidth.org>

Copyright (c) 2015-2016 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.  For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

*/

package main

import (
	"crypto/md5"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// ProxyFileRequest is a structure sent down a channel to the goroutine that is listening for
// requests, it then responds on the channel when the file is downloaded and ready to proxy.
type ProxyFileRequest struct {
	Token     string
	SourceURL string
	Response  chan *ProxyFile
}

// ProxyFile represents a single file that we're keeping track of.
type ProxyFile struct {
	FetchLock sync.RWMutex
	LocalPath string
	SourceURL string
	LastCheck time.Time
}

var (
	PROXY_FILE_REQ chan *ProxyFileRequest
	CACHE_FOR      time.Duration = time.Duration(86400 * time.Second)
	CACHE_DIR      string        = "/tmp"
	MAXIMUM_SIZE   int64         = 20 * 1024 * 1024
	MESSAGE_SALT   string        = "You should really use a salt file!"
	HOTLINK_DOMAIN string        = "example.org"
)

func main() {
	var port = flag.Int("port", 6250, "Port to listen on")
	var listen = flag.String("listen", "0.0.0.0", "IP to listen on")
	var cacheDir = flag.String("cache_dir", CACHE_DIR, "Directory to cache in")
	var cacheFor = flag.Int("cache_for", int(CACHE_FOR/1000000000),
		"How long to cache files for (seconds)")
	var maxSize = flag.Int64("max_filesize", MAXIMUM_SIZE, "Max filesyze in bytes to proxy")
	var hotlinkDomain = flag.String("hotlink_domain", HOTLINK_DOMAIN,
		"Domain to allow hotlinking from")
	var saltFile = flag.String("salt_file", "", "Path to salt file to use for signatures")
	flag.Parse()

	CACHE_FOR = time.Duration(*cacheFor) * time.Second
	CACHE_DIR = *cacheDir
	MAXIMUM_SIZE = *maxSize
	HOTLINK_DOMAIN = *hotlinkDomain

	stat, err := os.Stat(CACHE_DIR)
	if err != nil || !stat.Mode().IsDir() {
		log.Fatalf("Cache directory not found: %s", CACHE_DIR)
	}

	if *saltFile != "" {
		temp_salt, err := ioutil.ReadFile(*saltFile)
		if err != nil {
			log.Fatalf("Failed to get salt from file %s: %s", *saltFile, err)
		}
		MESSAGE_SALT = string(temp_salt)
	}

	PROXY_FILE_REQ = make(chan *ProxyFileRequest, 10)
	go handleProxyFileRequests()
	go cleanCacheFiles()

	log.Printf("Listening on %s:%d", *listen, *port)
	log.Printf("Caching to %s with a max of %d nanoseconds", CACHE_DIR, CACHE_FOR)

	http.HandleFunc("/robots.txt", robotsHandler)
	http.HandleFunc("/", defaultHandler)
	http.ListenAndServe(fmt.Sprintf("%s:%d", *listen, *port), nil)
}

func cleanCacheFiles() {
	timer := time.NewTicker(5 * time.Minute)
	defer timer.Stop()

	for range timer.C {
		log.Printf("Initiating scheduled cache clean...")
		infos, err := ioutil.ReadDir(CACHE_DIR)
		if err != nil {
			log.Printf("Failed to Readdir: %s", err)
			continue
		}

		for _, info := range infos {
			if !info.Mode().IsRegular() || strings.HasPrefix(info.Name(), ".") {
				continue
			}
			if info.ModTime().Before(time.Now().Add(-CACHE_FOR)) {
				// File has expired, remove it
				// TODO: There is maybe a race here with the handler, if someone requests this
				// exactly when it expires and we happen to run and ... unlikely, and if this
				// happens it will just 404 to the user and a refresh will fix it.
				log.Printf("Removing expired cache file: %s", info.Name())
				if err := os.Remove(filepath.Join(CACHE_DIR, info.Name())); err != nil {
					log.Printf("Error removing cache file %s: %s", info.Name(), err)
				}
			}
		}
	}
}

func robotsHandler(w http.ResponseWriter, req *http.Request) {
	log.Printf("Request for robots.txt from User-Agent: %s", req.Header.Get("User-Agent"))
	fmt.Fprint(w, "User-agent: *\nDisallow: /\n")
}

func defaultHandler(w http.ResponseWriter, req *http.Request) {
	//                        0   /  1  /   2  /   3   /  4
	// https://proxy.dreamwidth.net/TOKEN/SOURCE/foo.com/url?arg=val
	// SOURCE is ignored programmatically; it's only for admins
	parts := strings.SplitN(req.URL.RequestURI(), "/", 5)

	if len(parts) != 5 || parts[0] != "" {
		// Invalid request, treat it as a 404.
		log.Printf("Invalid request: %s", req.URL.RequestURI())
		http.NotFound(w, req)
		return
	}
	token, orig_url := parts[1], "http://"+strings.Join(parts[3:], "/")

	if !validSignature(token, orig_url) {
		log.Printf("Invalid signature in request: %s", req.URL.RequestURI())
		http.NotFound(w, req)
		return
	}

	referer := req.Header.Get("Referer")
	if referer != "" {
		ref_url, err := url.Parse(referer)
		if err != nil {
			log.Printf("Rejecting malformed referer [%s]: %s", referer, err)
			http.Error(w, "Malformed referer.", 400)
			return
		}
		host, _, err := net.SplitHostPort(ref_url.Host)
		if err != nil {
			host = ref_url.Host
		}
		if !(host == HOTLINK_DOMAIN || strings.HasSuffix(host, "."+HOTLINK_DOMAIN)) {
			log.Printf("Rejecting hotlink from: %s", referer)
			http.Error(w, "Hotlinking is forbidden.", 403)
			return
		}
	}

	path, err := getProxyFile(token, orig_url)
	if err != nil {
		http.Error(w, fmt.Sprintf("%s", err), 500)
		return
	}

	http.ServeFile(w, req, path)
}

func validSignature(token, orig_url string) bool {
	signature := fmt.Sprintf("%x", md5.Sum([]byte(MESSAGE_SALT+orig_url)))[0:12]
	log.Printf("Signature check for %s: expect %s", orig_url, signature)
	return token == signature
}

func getProxyFile(token, orig_url string) (string, error) {
	respch := make(chan *ProxyFile)
	PROXY_FILE_REQ <- &ProxyFileRequest{
		Token:     token,
		SourceURL: orig_url,
		Response:  respch,
	}
	pf := <-respch

	// We have to lock the pf before doing anything on it, to prevent clobbering other people
	// who might be trying to use it. Start with a read lock.
	pf.FetchLock.RLock()
	if pf.LocalPath != "" {
		if time.Since(pf.LastCheck) > CACHE_FOR {
			// Do nothing. We just want to avoid returning now.
		} else {
			defer pf.FetchLock.RUnlock()
			return pf.LocalPath, nil
		}
	}

	// LocalPath was false, which means we want to try to upgrade to a writer and download it,
	// since possibly we're the first person to touch it.
	pf.FetchLock.RUnlock()
	pf.FetchLock.Lock()
	defer pf.FetchLock.Unlock()

	// Of course, the above is racy -- someone else might have beaten us to the lock, so let's
	// check again and make sure we need to download it.
	if pf.LocalPath != "" {
		if time.Since(pf.LastCheck) > CACHE_FOR {
			log.Printf("Expiring local cache for: %s", orig_url)
		} else {
			return pf.LocalPath, nil
		}
	}

	// Needs downloading and we have the right/write lock.
	resp, err := http.Get(orig_url)
	if err != nil {
		log.Printf("Failed to fetch %s: %s", orig_url, err)
		return "", err
	}
	defer resp.Body.Close()

	// If it's too large, we don't want it!
	if resp.ContentLength > MAXIMUM_SIZE {
		log.Printf("File too large %s: %d", orig_url, resp.ContentLength)
		return "", errors.New("File exceeds maximum allowable size")
	}

	// Make sure the file we requested is an image:
	// 1. Get the first 512 (or less) bytes of the content
	var firstblock []byte = make([]byte, 512)
	n, _ := io.ReadFull(resp.Body, firstblock)
	firstblock = firstblock[:n]

	// Make sure the file we requested is an image:
	// 2. See if the content begins with an image MIME type
	mimetype := http.DetectContentType(firstblock)
	if !strings.HasPrefix(mimetype, "image/") {
		log.Printf("Not an image %s: %s", orig_url, mimetype)
		return "", errors.New("File is not a known image type")
	}

	// Prepare to write the file out to disk.
	fn := filepath.Join(CACHE_DIR, fmt.Sprintf("%x", md5.Sum([]byte(orig_url))))
	file, err := os.Create(fn)
	if err != nil {
		log.Printf("Failed to open %s for writing: %s", fn, err)
		return "", err
	}
	defer file.Close()

	// First write the chunk we already read from the response.
	written1, err := io.WriteString(file, string(firstblock))
	if err != nil {
		log.Printf("Failed to cache file %s: %s", orig_url, err)
		return "", err
	}
	if written1 != n {
		log.Printf("Failed to cache file %s: first block failed at %d / %d",
			orig_url, written1, n)
		return "", errors.New("Writing first block failed")
	}

	// Now write out the remainder of the response content.
	written, err := io.Copy(file, resp.Body)
	if err != nil {
		log.Printf("Failed to cache file %s: %s", orig_url, err)
		return "", err
	}

	// Fill in the file structure, since we've got everything.
	pf.LocalPath = fn
	pf.SourceURL = orig_url
	pf.LastCheck = time.Now()

	log.Printf("Cached %s to %s: %d bytes", pf.SourceURL, pf.LocalPath, int64(written1)+written)
	return pf.LocalPath, nil
}

// handleProxyFileRequests is just the routine that manages the proxyFiles structure.
func handleProxyFileRequests() {
	proxyFiles := make(map[string]*ProxyFile)
	for {
		req := <-PROXY_FILE_REQ

		resp, ok := proxyFiles[req.Token]
		if ok {
			req.Response <- resp
			continue
		}

		// See if file is already in cache
		fn := filepath.Join(CACHE_DIR, fmt.Sprintf("%x", md5.Sum([]byte(req.SourceURL))))
		if info, err := os.Stat(fn); err == nil && info.Mode().IsRegular() {
			// See if file is modified more recently than CACHE_FOR, if so return
			if info.ModTime().After(time.Now().Add(-CACHE_FOR)) {
				log.Printf("Returning cached %s: %d bytes", fn, info.Size())
				resp = &ProxyFile{
					SourceURL: req.SourceURL,
					LocalPath: fn,
					LastCheck: info.ModTime(),
				}
				proxyFiles[req.Token] = resp
				req.Response <- resp
				continue
			}
		}

		// File not local or expired, re-fetch
		resp = &ProxyFile{
			SourceURL: req.SourceURL,
		}
		proxyFiles[req.Token] = resp
		req.Response <- resp
	}
}
