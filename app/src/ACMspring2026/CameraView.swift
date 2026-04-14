import SwiftUI
import UIKit
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    
    @Binding var image: UIImage?
    @Binding var triggerCapture: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        if triggerCapture {
            uiViewController.capturePhoto()
            DispatchQueue.main.async {
                triggerCapture = false
            }
        }
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            parent.image = image
        }
    }
}

protocol CameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    weak var delegate: CameraViewControllerDelegate?
    
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        addTapGesture()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        captureSession.stopRunning()
    }
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.addInput(input)
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            previewLayer.session = captureSession
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
    
    private func addTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(capturePhotoInternal))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func capturePhotoInternal() {
        capturePhoto()
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        delegate?.didCaptureImage(image)
    }
}
