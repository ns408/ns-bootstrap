#!/usr/bin/env bash
# OpenSSL/TLS utility functions

# Display PEM certificate contents
function openssl_display_cert_content_pem() {
  openssl x509 -in "$1" -text
}

# Display DER certificate contents
function openssl_display_cert_content_der() {
  openssl x509 -in "$1" -inform der -text
}

# Create a self-signed certificate
function openssl_created_self_signed_cert() {
  openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout privateKey.key -out certificate.crt
}

# Check a Certificate Signing Request (CSR)
function openssl_check_csr() {
  openssl req -text -noout -verify -in "$1"
}

# Check a private key
function openssl_check_privkey() {
  openssl rsa -in "$1" -check
}
