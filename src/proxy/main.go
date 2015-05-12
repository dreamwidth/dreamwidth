/*

main.go

This is a simple caching proxy. This is designed for the Dreamwidth project to
allow us to proxy HTTP embedded content.

Authors:
     Mark Smith <mark@dreamwidth.org>

Copyright (c) 2015 by Dreamwidth Studios, LLC.

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
	"net/http"
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
	CACHE_FOR      time.Duration = time.Duration(3600 * time.Second)
	CACHE_DIR      string        = "/tmp"
	MAXIMUM_SIZE   int64         = 20 * 1024 * 1024
	MESSAGE_SALT   string        = "You should really use a salt file!"
)

func main() {
	var port = flag.Int("port", 6250, "Port to listen on")
	var listen = flag.String("listen", "0.0.0.0", "IP to listen on")
	var cacheDir = flag.String("cache_dir", CACHE_DIR, "Directory to cache in")
	var cacheFor = flag.Int("cache_for", int(CACHE_FOR/1000000000),
		"How long to cache files for (seconds)")
	var maxSize = flag.Int64("max_filesize", MAXIMUM_SIZE, "Max filesyze in bytes to proxy")
	var saltFile = flag.String("salt_file", "", "Path to salt file to use for signatures")
	flag.Parse()

	CACHE_FOR = time.Duration(*cacheFor) * time.Second
	CACHE_DIR = *cacheDir
	MAXIMUM_SIZE = *maxSize

	stat, err := os.Stat(CACHE_DIR)
	if !stat.Mode().IsDir() || err != nil {
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

	log.Printf("Listening on %s:%d", *listen, *port)
	log.Printf("Caching to %s with a max of %d nanoseconds", CACHE_DIR, CACHE_FOR)

	http.HandleFunc("/", defaultHandler)
	http.ListenAndServe(fmt.Sprintf("%s:%d", *listen, *port), nil)
}

func defaultHandler(w http.ResponseWriter, req *http.Request) {
	//                        0   /  1  /   2   /  3
	// http://proxy.dreamwidth.net/TOKEN/foo.com/url?arg=val
	parts := strings.SplitN(req.URL.RequestURI(), "/", 4)
	if len(parts) != 4 || parts[0] != "" {
		// Invalid request, treat it as a 404.
		log.Printf("Invalid request: %s", req.URL.RequestURI())
		http.NotFound(w, req)
		return
	}
	token, url := parts[1], "http://"+strings.Join(parts[2:], "/")

	if !validSignature(token, url) {
		log.Printf("Invalid signature in request: %s", req.URL.RequestURI())
		http.NotFound(w, req)
		return
	}

	path, err := getProxyFile(token, url)
	if err != nil {
		http.Error(w, fmt.Sprintf("%s", err), 500)
		return
	}

	http.ServeFile(w, req, path)
}

func validSignature(token, url string) bool {
	signature := fmt.Sprintf("%x", md5.Sum([]byte(MESSAGE_SALT+url)))[0:12]
	log.Printf("Signature check for %s: expect %s", url, signature)
	return token == signature
}

func getProxyFile(token, url string) (string, error) {
	respch := make(chan *ProxyFile)
	PROXY_FILE_REQ <- &ProxyFileRequest{
		Token:     token,
		SourceURL: url,
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
			log.Printf("Expiring local cache for: %s", url)
		} else {
			return pf.LocalPath, nil
		}
	}

	// Needs downloading and we have the right/write lock.
	resp, err := http.Get(url)
	if err != nil {
		log.Printf("Failed to fetch %s: %s", url, err)
		return "", err
	}
	defer resp.Body.Close()

	// If it's too large, we don't want it!
	if resp.ContentLength > MAXIMUM_SIZE {
		log.Printf("File too large %s: %d", url, resp.ContentLength)
		return "", errors.New("File exceeds maximum allowable size")
	}

	// Write the file out to disk.
	fn := filepath.Join(CACHE_DIR, fmt.Sprintf("%x", md5.Sum([]byte(url))))
	file, err := os.Create(fn)
	if err != nil {
		log.Printf("Failed to open %s for writing: %s", fn, err)
		return "", err
	}

	written, err := io.Copy(file, resp.Body)
	if err != nil {
		file.Close()
		log.Printf("Failed to cache file %s: %s", url, err)
		return "", err
	}
	file.Close()

	// Fill in the file structure, since we've got everything.
	pf.LocalPath = fn
	pf.SourceURL = url
	pf.LastCheck = time.Now()

	log.Printf("Cached %s to %s: %d bytes", pf.SourceURL, pf.LocalPath, written)
	return pf.LocalPath, nil
}

// handleProxyFileRequests is just the routine that manages the proxyFiles structure.
func handleProxyFileRequests() {
	proxyFiles := make(map[string]*ProxyFile)
	for {
		req := <-PROXY_FILE_REQ

		resp, ok := proxyFiles[req.Token]
		if !ok {
			resp = &ProxyFile{
				SourceURL: req.SourceURL,
			}
			proxyFiles[req.Token] = resp
		}

		req.Response <- resp
	}
}
