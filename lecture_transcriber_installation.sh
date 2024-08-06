#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is designed for macOS. Exiting."
    exit 1
fi

# Determine if we're on Apple Silicon
if [[ $(uname -m) == 'arm64' ]]; then
    IS_APPLE_SILICON=true
else
    IS_APPLE_SILICON=false
fi

# Install Xcode Command Line Tools if not already installed
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install

    # Wait for the installation to complete
    echo "Please follow the prompts to install Xcode Command Line Tools."
    echo "Press any key when the installation is complete."
    read -n 1 -s -r
else
    echo "Xcode Command Line Tools are already installed."
fi

# Install Homebrew if not present
if ! command_exists brew; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew is already installed."
fi

# Make sure Homebrew is in PATH
if $IS_APPLE_SILICON; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Install system dependencies
BREW_PACKAGES="ffmpeg openai-whisper ollama perl"
for package in $BREW_PACKAGES; do
    if ! command_exists $package; then
        echo "Installing $package..."
        brew install $package
    else
        echo "$package is already installed."
    fi
done

# Set up PATH for Homebrew Perl
if $IS_APPLE_SILICON; then
    echo 'export PATH="/opt/homebrew/opt/perl/bin:$PATH"' >> ~/.zshrc
    source ~/.zshrc
else
    echo 'export PATH="/usr/local/opt/perl/bin:$PATH"' >> ~/.zshrc
    source ~/.zshrc
fi

# Install cpanm
if ! command_exists cpanm; then
    echo "Installing cpanm..."
    curl -L https://cpanmin.us | perl - --sudo App::cpanminus
else
    echo "cpanm is already installed."
fi

# Install Perl modules
PERL_MODULES="File::Basename File::Path Getopt::Long HTTP::Tiny JSON::PP Encode YAML::XS MIME::Base64"
echo "Installing Perl modules..."
if $IS_APPLE_SILICON; then
    arch -arm64 cpanm $PERL_MODULES
else
    cpanm $PERL_MODULES
fi

# Download the Lecture Transcriber script
echo "Downloading Lecture Transcriber script..."
curl -O https://raw.githubusercontent.com/aendress/lecture_transcriber/main/lecture_transcriber.pl
chmod +x lecture_transcriber.pl

echo "Installation complete. You can now run the Lecture Transcriber script using:"
echo "./lecture_transcriber.pl [options] input.mp4"
