# LLMtest - Universal Local LLM Chat App

A cross-platform chat application that runs Large Language Models (LLMs) locally on iOS, iPadOS, and macOS using llama.cpp.

## Features

- 🤖 **Local LLM Inference** - Run models completely offline using llama.cpp
- 🌐 **Universal App** - Single codebase for iPhone, iPad, and Mac
- 💬 **Multiple Conversations** - Organize chats with different topics
- 📱 **Platform-Adaptive UI** - Native interface for each platform
- 🔒 **Privacy-First** - All processing happens on-device
- ⚡ **Optimized Performance** - Memory-efficient settings for mobile devices
- 📤 **Export Conversations** - Save chats as text files

## Supported Platforms

- **iOS 17.0+** (iPhone)
- **iPadOS 17.0+** (iPad) 
- **macOS 14.0+** (Mac, including Apple Silicon and Intel)

## Supported Models

The app supports GGUF format models. Tested with:
- TinyLlama 1.1B Chat
- Phi-3 Mini 4K Instruct
- Qwen2.5 0.5B Instruct

## Architecture

- **Swift/SwiftUI** - Modern declarative UI framework
- **llama.cpp** - High-performance LLM inference engine
- **C Bridge** - Interface between Swift and llama.cpp
- **Platform-Specific Libraries** - Optimized builds for each target

## Setup Instructions

### Prerequisites

- Xcode 15.0+
- macOS 14.0+
- CMake 3.20+

### Building from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/LLMtest.git
   cd LLMtest
   ```

2. **Initialize llama.cpp submodule:**
   ```bash
   git submodule update --init --recursive
   ```

3. **Build llama.cpp libraries:**
   ```bash
   # For macOS
   cd llama.cpp
   mkdir build && cd build
   cmake .. -DCMAKE_BUILD_TYPE=Release
   make -j$(sysctl -n hw.ncpu)
   
   # For iOS (if needed)
   mkdir build_ios && cd build_ios
   cmake .. -G Xcode -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DLLAMA_CURL=OFF \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=OFF \
            -DLLAMA_BUILD_TOOLS=OFF
   xcodebuild -configuration Release
   ```

4. **Download models:**
   - Place GGUF model files in the project root
   - Recommended: TinyLlama for testing (smaller size)

5. **Open in Xcode:**
   ```bash
   open LLMtest.xcodeproj
   ```

6. **Build and run** - Select your target platform and run!

## Project Structure

```
LLMtest/
├── LLMtest/                    # Main app source
│   ├── ContentView.swift       # Main UI
│   ├── LlamaWrapper.swift      # Swift interface to llama.cpp
│   ├── Config.swift           # App configuration
│   ├── llama_bridge.c         # C bridge to llama.cpp
│   ├── llama_bridging.h       # Bridge header
│   └── llama/                 # llama.cpp headers
├── LLMtest.xcodeproj/         # Xcode project
├── Models/                    # GGUF model files (gitignored)
└── README.md
```

## Platform-Specific Features

### iOS/iPadOS
- Touch-optimized interface
- NavigationView with master-detail flow
- Document-based file exports
- Memory-optimized model loading

### macOS
- Mouse and keyboard optimized
- NavigationSplitView with sidebar
- Native save dialogs
- Full GPU acceleration support

## Performance Optimization

The app uses conservative settings optimized for mobile devices:
- **Context Size**: 256 tokens (iOS) / 1024 tokens (macOS)
- **Batch Size**: 32 (iOS) / 128 (macOS)
- **Memory Mapping**: Disabled on iOS for compatibility
- **GPU Layers**: CPU-only on iOS, GPU-accelerated on macOS

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on multiple platforms
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - The core inference engine
- [Hugging Face](https://huggingface.co/) - Model hosting and community
- Apple - SwiftUI and development tools

## Troubleshooting

### Common Issues

**Model loading fails on iOS:**
- Ensure model file is under 2GB
- Try TinyLlama for testing
- Check iOS Simulator logs

**Build errors:**
- Update Xcode to latest version
- Clean build folder (⌘+Shift+K)
- Verify CMake installation

**Performance issues:**
- Reduce context size in Config.swift
- Use smaller models for testing
- Monitor memory usage in Instruments

For more help, please open an issue on GitHub. 