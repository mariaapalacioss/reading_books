import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    SmartBooksOcr.register(messenger: messenger)
  }
}

enum SmartBooksOcr {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "smart_books/ocr",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeBgra",
            let args = call.arguments as? [String: Any],
            let width = args["width"] as? Int,
            let height = args["height"] as? Int,
            let data = args["pixels"] as? FlutterStandardTypedData else {
        result(FlutterMethodNotImplemented)
        return
      }

      recognize(
        bgra: data.data,
        width: width,
        height: height,
        result: result
      )
    }
  }

  private static func recognize(
    bgra: Data,
    width: Int,
    height: Int,
    result: @escaping FlutterResult
  ) {
    let bytesPerRow = width * 4

    guard let provider = CGDataProvider(data: bgra as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
              rawValue:
                CGImageAlphaInfo.premultipliedFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) else {
      result(
        FlutterError(
          code: "ocr",
          message: "No se pudo crear imagen",
          details: nil
        )
      )
      return
    }

    let request = VNRecognizeTextRequest { req, err in
      if let err = err {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr",
              message: err.localizedDescription,
              details: nil
            )
          )
        }
        return
      }

      let observations = req.results as? [VNRecognizedTextObservation] ?? []
      var words: [[String: Any]] = []

      for obs in observations {
        guard let top = obs.topCandidates(1).first else {
          continue
        }

        let box = obs.boundingBox

        words.append([
          "text": top.string,
          "x0": box.minX * Double(width),
          "y0": (1.0 - box.maxY) * Double(height),
          "x1": box.maxX * Double(width),
          "y1": (1.0 - box.minY) * Double(height),
        ])
      }

      DispatchQueue.main.async {
        result(words)
      }
    }

    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["es-ES", "en-US"]

    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      options: [:]
    )

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}