#!/bin/bash

# OpenOats Build Script
# Usage: ./build.sh [debug|release|test|clean|all]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/OpenOats"

# Default build type
BUILD_TYPE="${1:-all}"

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if we're in the right directory
    if [ ! -f "${PROJECT_DIR}/Package.swift" ]; then
        print_error "Package.swift not found in ${PROJECT_DIR}"
        print_error "Please run this script from the OpenOats repository root"
        exit 1
    fi
    
    # Check Swift version
    if ! command -v swift &> /dev/null; then
        print_error "Swift not found. Please install Xcode."
        exit 1
    fi
    
    SWIFT_VERSION=$(swift --version | head -n 1)
    print_success "Found: ${SWIFT_VERSION}"
    
    # Check Xcode developer directory
    if ! xcode-select -p &> /dev/null; then
        print_warning "Xcode developer directory not set"
        print_warning "Run: sudo xcode-select -s /Applications/Xcode.app"
    else
        XCODE_PATH=$(xcode-select -p)
        print_success "Xcode: ${XCODE_PATH}"
    fi
    
    echo ""
}

clean_build() {
    print_header "Cleaning Build Artifacts"
    
    cd "${PROJECT_DIR}"
    
    # Clean Swift Package Manager build
    swift package clean 2>/dev/null || true
    
    # Remove build directories
    rm -rf .build/debug .build/release
    
    print_success "Build artifacts cleaned"
    echo ""
}

build_debug() {
    print_header "Building Debug Version"
    
    cd "${PROJECT_DIR}"
    
    echo "Starting debug build..."
    if swift build 2>&1 | tee /tmp/build_debug.log; then
        print_success "Debug build completed successfully!"
        print_success "Binary location: .build/debug/OpenOats"
        
        # Show binary size
        if [ -f ".build/debug/OpenOats" ]; then
            BINARY_SIZE=$(du -h .build/debug/OpenOats | cut -f1)
            print_success "Binary size: ${BINARY_SIZE}"
        fi
    else
        print_error "Debug build failed!"
        print_error "Check /tmp/build_debug.log for details"
        exit 1
    fi
    
    echo ""
}

build_release() {
    print_header "Building Release Version"
    
    cd "${PROJECT_DIR}"
    
    echo "Starting release build (this may take 2-3 minutes)..."
    if swift build -c release 2>&1 | tee /tmp/build_release.log; then
        print_success "Release build completed successfully!"
        print_success "Binary location: .build/release/OpenOats"
        
        # Show binary size
        if [ -f ".build/release/OpenOats" ]; then
            BINARY_SIZE=$(du -h .build/release/OpenOats | cut -f1)
            print_success "Binary size: ${BINARY_SIZE}"
        fi
    else
        print_error "Release build failed!"
        print_error "Check /tmp/build_release.log for details"
        exit 1
    fi
    
    echo ""
}

run_tests() {
    print_header "Running Tests"
    
    cd "${PROJECT_DIR}"
    
    echo "Running all tests (this may take ~70 seconds)..."
    if swift test --parallel 2>&1 | tee /tmp/test_results.log; then
        # Extract test summary
        TEST_SUMMARY=$(grep "Executed.*tests" /tmp/test_results.log | tail -1)
        print_success "Tests completed: ${TEST_SUMMARY}"
        
        # Check for failures
        if grep -q "with 0 failures" /tmp/test_results.log; then
            print_success "All tests passed!"
        else
            print_warning "Some tests may have failed - check output above"
        fi
    else
        print_error "Tests failed!"
        print_error "Check /tmp/test_results.log for details"
        exit 1
    fi
    
    echo ""
}

show_help() {
    echo "OpenOats Build Script"
    echo ""
    echo "Usage: ./build.sh [command]"
    echo ""
    echo "Commands:"
    echo "  debug    - Build debug version only"
    echo "  release  - Build release version only"
    echo "  test     - Run tests only"
    echo "  clean    - Clean build artifacts"
    echo "  all      - Clean, build debug, build release, and run tests (default)"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./build.sh              # Run full build pipeline"
    echo "  ./build.sh debug        # Quick debug build"
    echo "  ./build.sh test         # Run tests only"
    echo "  ./build.sh clean        # Clean everything"
    echo ""
}

# Main execution
case "${BUILD_TYPE}" in
    debug)
        check_prerequisites
        build_debug
        ;;
    release)
        check_prerequisites
        build_release
        ;;
    test)
        check_prerequisites
        run_tests
        ;;
    clean)
        clean_build
        ;;
    all)
        check_prerequisites
        clean_build
        build_debug
        build_release
        run_tests
        print_header "Build Pipeline Complete!"
        echo -e "${GREEN}Debug binary:${NC}   ${PROJECT_DIR}/.build/debug/OpenOats"
        echo -e "${GREEN}Release binary:${NC} ${PROJECT_DIR}/.build/release/OpenOats"
        echo ""
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    *)
        print_error "Unknown command: ${BUILD_TYPE}"
        show_help
        exit 1
        ;;
esac

print_success "Done!"
