import 'dart:io';

enum ChatGptPlatformSupport {
  /// Flujo OSS loopback documentado (127.0.0.1 — macOS e iOS).
  ossLoopback,

  unsupported,
}

ChatGptPlatformSupport chatGptPlatformSupport() {
  if (Platform.isMacOS || Platform.isIOS) {
    return ChatGptPlatformSupport.ossLoopback;
  }
  return ChatGptPlatformSupport.unsupported;
}

String chatGptPlatformLabel(ChatGptPlatformSupport support) {
  switch (support) {
    case ChatGptPlatformSupport.ossLoopback:
      if (Platform.isIOS) {
        return 'iOS · Sign in with ChatGPT (loopback OSS, igual que macOS)';
      }
      return 'macOS · Sign in with ChatGPT (loopback oficial OSS)';
    case ChatGptPlatformSupport.unsupported:
      return 'Plataforma no soportada';
  }
}

bool get chatGptConnectEnabled =>
    chatGptPlatformSupport() == ChatGptPlatformSupport.ossLoopback;
