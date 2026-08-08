#!/bin/bash

# ============================================
# Rapid Mesh - Build Script
# ============================================
# This script builds the release APK for Rapid Mesh
# Usage: ./build.sh [options]
#
# Options:
#   --release     Build release APK (default)
#   --debug       Build debug APK
#   --clean       Clean build directory before building
#   --install     Install on connected device after build
#   --help        Show this help message
# ============================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
BUILD_TYPE="release"
CLEAN_BUILD=false
INSTALL_AFTER=false
FLAVOR="production"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --debug)
            BUILD_TYPE="debug"
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --install)
            INSTALL_AFTER=true
            shift
            ;;
        --help)
            echo "Rapid Mesh Build Script"
            echo ""
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  --release     Build release APK (default)"
            echo "  --debug       Build debug APK"
            echo "  --clean       Clean build directory before building"
            echo "  --install     Install on connected device after build"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Rapid Mesh - Android APK Builder${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check Flutter installation
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter is not installed or not in PATH${NC}"
    echo ""
    echo "Please install Flutter first:"
    echo "  https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo -e "${GREEN}✓ Flutter version:${NC} $(flutter --version | head -1)"
echo ""

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: pubspec.yaml not found${NC}"
    echo "Please run this script from the rapid-mesh root directory"
    exit 1
fi

# Make sure the Gradle wrapper exists (missing files are regenerated, e.g. gradle-wrapper.jar)
if [ ! -f "android/gradle/wrapper/gradle-wrapper.jar" ]; then
    echo -e "${YELLOW}⚠ Gradle wrapper jar missing - running 'flutter create' to regenerate it...${NC}"
    flutter create --platforms=android --org com.rapidmesh .
fi

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}🧹 Cleaning build directory...${NC}"
    flutter clean
fi

# Get dependencies
echo -e "${YELLOW}📦 Installing dependencies...${NC}"
flutter pub get

# Check for Android SDK
echo -e "${YELLOW}🔍 Checking Android SDK...${NC}"

if [ ! -d "$ANDROID_HOME" ] && [ ! -d "$ANDROID_SDK_ROOT" ] && [ ! -d "$HOME/Android/Sdk" ]; then
    echo -e "${RED}❌ Android SDK not found${NC}"
    echo "Please install Android SDK and set ANDROID_HOME"
    exit 1
fi

echo -e "${GREEN}✓ Android SDK found${NC}"
echo ""

# Build the APK
echo -e "${YELLOW}🔨 Building ${BUILD_TYPE} APK (flavor: $FLAVOR)...${NC}"
echo "This may take a few minutes..."
echo ""

if [ "$BUILD_TYPE" = "release" ]; then
    flutter build apk --release --flavor "$FLAVOR"
else
    flutter build apk --debug --flavor "$FLAVOR"
fi

APK_PATH="build/app/outputs/flutter-apk/app-${FLAVOR}-${BUILD_TYPE}.apk"

if [ -f "$APK_PATH" ]; then
    APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   ✅ BUILD SUCCESSFUL!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "APK Location: ${BLUE}$APK_PATH${NC}"
    echo -e "APK Size: ${BLUE}$APK_SIZE${NC}"
    echo ""

    # Copy to downloads folder
    mkdir -p downloads
    cp "$APK_PATH" "downloads/RapidMesh_${BUILD_TYPE}_$(date +%Y%m%d_%H%M%S).apk"
    echo -e "Also copied to: ${BLUE}downloads/${NC}"

    # Install if requested
    if [ "$INSTALL_AFTER" = true ]; then
        echo ""
        echo -e "${YELLOW}📱 Installing on device...${NC}"

        # Check for connected device
        DEVICES=$(adb devices | tail -n +2 | grep -c 'device$' || true)

        if [ "$DEVICES" -eq 0 ]; then
            echo -e "${RED}❌ No device connected. Please connect your Android device.${NC}"
        else
            adb install -r "$APK_PATH"
            echo -e "${GREEN}✓ Installed successfully!${NC}"
        fi
    fi

    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Transfer the APK to your phone (USB, email, etc.)"
    echo "2. Enable 'Install from Unknown Sources' in Android settings"
    echo "3. Open the APK file to install"
    echo ""
    echo -e "${BLUE}For GitHub deployment:${NC}"
    echo "1. Create a new repository on GitHub"
    echo "2. Push this code to GitHub"
    echo "3. Go to Releases → Create new Release"
    echo "4. Upload the APK from: $APK_PATH"

else
    echo -e "${RED}❌ Build failed! APK not found at $APK_PATH${NC}"
    exit 1
fi
