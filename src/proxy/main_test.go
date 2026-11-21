/*

main_test.go

Tests for the Dreamwidth image proxy.

Authors:
     Dreamwidth contributors

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.  For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

*/

package main

import (
	"bytes"
	"crypto/md5"
	"fmt"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestDefaultHandlerUnavailableImage(t *testing.T) {
	var sourceImage bytes.Buffer
	if err := png.Encode(&sourceImage, image.NewRGBA(image.Rect(0, 0, 1, 1))); err != nil {
		t.Fatal(err)
	}
	var sourceAvailable atomic.Bool
	source := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if !sourceAvailable.Load() {
			http.Error(response, "Private image", http.StatusForbidden)
			return
		}
		response.Header().Set("Content-Type", "image/png")
		response.Write(sourceImage.Bytes())
	}))
	defer source.Close()

	previousCacheDir, previousRequests := CACHE_DIR, PROXY_FILE_REQ
	requests := make(chan *ProxyFileRequest)
	workerDone := make(chan struct{})
	CACHE_DIR, PROXY_FILE_REQ = t.TempDir(), requests
	go func() {
		defer close(workerDone)
		handleProxyFileRequests(requests)
	}()
	t.Cleanup(func() {
		close(requests)
		<-workerDone
		CACHE_DIR, PROXY_FILE_REQ = previousCacheDir, previousRequests
	})

	sourceURL := source.URL + "/private.png"
	token := fmt.Sprintf("%x", md5.Sum([]byte(MESSAGE_SALT+sourceURL)))[:12]
	proxyPath := "/" + token + "/test/" + strings.TrimPrefix(sourceURL, "http://")
	request := httptest.NewRequest(http.MethodGet, proxyPath, nil)
	failure := httptest.NewRecorder()
	defaultHandler(failure, request)

	if failure.Code != http.StatusOK {
		t.Errorf("unavailable image returned status %d; want %d", failure.Code, http.StatusOK)
	}
	if contentType := failure.Header().Get("Content-Type"); contentType != "image/svg+xml" {
		t.Errorf("unavailable image content type = %q; want image/svg+xml", contentType)
	}
	if !strings.Contains(failure.Body.String(), "Image unavailable") {
		t.Error("placeholder does not explain why the image is missing")
	}
	if policy := failure.Header().Get("Cache-Control"); policy != "no-store" {
		t.Errorf("unavailable image cache policy = %q; want no-store", policy)
	}

	sourceAvailable.Store(true)
	retry := httptest.NewRecorder()
	defaultHandler(retry, request)
	if retry.Code != http.StatusOK || !bytes.Equal(retry.Body.Bytes(), sourceImage.Bytes()) {
		t.Errorf("retry returned status %d and content type %q; want original PNG", retry.Code, retry.Header().Get("Content-Type"))
	}
}
