//
//  ViewController.m
//  tesseract
//
//  Created by Albert Nadal Garriga on 05/06/13.
//  Copyright (c) 2013 Albert Nadal Garriga. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "Tesseract.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) IBOutlet UITextView *textView;
@property (nonatomic, strong) IBOutlet UIImageView *cameraImageView;
@property (nonatomic, strong) IBOutlet UIButton *recognizeButton;
@property (nonatomic, strong) IBOutlet UIView *loadingView;
@property (nonatomic, weak) IBOutlet UIView *roundedLoadingView;
@property (nonatomic, strong) IBOutlet UIButton *textToClipboardButton;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) Tesseract *tesseract;
@property (nonatomic, strong) dispatch_queue_t tesseractAccessQueue;

- (IBAction)recognizeText:(id)sender;
- (void)showRecognizedText;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _cameraImageView.clipsToBounds = YES;

    _roundedLoadingView.layer.cornerRadius = 6.0f;
    _roundedLoadingView.layer.masksToBounds = YES;

    [self.view bringSubviewToFront:_loadingView];
    [_loadingView setHidden:YES];

    _tesseractAccessQueue = dispatch_queue_create("com.lafruitera.tesseractAccessQueue", 0);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = ([documentPaths count] > 0) ? [documentPaths objectAtIndex:0] : nil;
    NSString *dataPath = [documentPath stringByAppendingPathComponent:@"tessdata"];

    if (![fileManager fileExistsAtPath:dataPath])
    {
        [fileManager createDirectoryAtPath:dataPath withIntermediateDirectories:YES attributes:nil error:NULL];

        NSArray *tesseractFiles = @[@"eng.cube.bigrams", @"eng.cube.fold", @"eng.cube.lm", @"eng.cube.nn", @"eng.cube.params", @"eng.cube.size", @"eng.cube.word-freq", @"eng.tesseract_cube.nn", @"eng.traineddata"];

        for(NSString *tesseractFile in tesseractFiles)
        {
            NSString *bundlePath = [[NSBundle bundleForClass:[self class]] bundlePath];
            NSString *tessdataFilePath = [bundlePath stringByAppendingPathComponent:tesseractFile];
            NSString *documentsDataPath = [dataPath stringByAppendingPathComponent:tesseractFile];

            if(tessdataFilePath)
            {
                [fileManager copyItemAtPath:tessdataFilePath toPath:documentsDataPath error:nil];
            }
        }
    }

    _tesseract = [[Tesseract alloc] initWithDataPath:@"tessdata" language:@"eng"];
    [_tesseract setVariableValue:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ,.:-()?¿!¡'*&%$@=<>{}-#\"" forKey:@"tessedit_char_whitelist"];

    [self setupCaptureSession];
}

- (void)setupCaptureSession
{
    NSError *error = nil;

    _session = [[AVCaptureSession alloc] init];
    _session.sessionPreset = AVCaptureSessionPresetiFrame1280x720; //AVCaptureSessionPreset352x288;
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                        error:&error];

    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
	captureVideoPreviewLayer.frame = CGRectMake(0, 0, 320, 568); //_cameraImageView.bounds;
	[_cameraImageView.layer addSublayer:captureVideoPreviewLayer];

    if (!input)
    {
        // Handle the error
    }

    [_session addInput:input];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    [_session addOutput:output];

    dispatch_queue_t queue = dispatch_queue_create("cameraQueue", NULL);
    [output setSampleBufferDelegate:self queue:queue];

    output.videoSettings = [NSDictionary dictionaryWithObject:  [NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    output.alwaysDiscardsLateVideoFrames = YES;
    [_session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    dispatch_sync(_tesseractAccessQueue, ^{
        @autoreleasepool {
            [_tesseract setImage:[self scaleAndRotateImage:[self imageFromSampleBuffer:sampleBuffer] withMaxWidth:720 withImageOrientation:UIImageOrientationRight]];
        }
    });
}

- (IBAction)recognizeText:(id)sender
{
    [_loadingView setHidden:NO];
    [_recognizeButton setHidden:YES];

    [_session stopRunning];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_sync(_tesseractAccessQueue, ^{
            [_tesseract recognize];

            [self performSelectorOnMainThread:@selector(showRecognizedText) withObject:nil waitUntilDone:YES];

            [_session startRunning];
        });
    });
}

- (IBAction)sendRecognizedTextToClipboard:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = _textView.text;
}

- (void)showRecognizedText
{
    [_textView setText:[_tesseract recognizedText]];
    [_loadingView setHidden:YES];
    [_recognizeButton setHidden:NO];
    [_textToClipboardButton setEnabled:YES];
}

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);

    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);

    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    // Is necessary to crop the image because we only want to translate the viewport area text
    CGRect clippedRect  = CGRectMake(0, 0, 590, 720);
    CGImageRef cropedImage = CGImageCreateWithImageInRect(quartzImage, clippedRect);
    UIImage *image = [UIImage imageWithCGImage:cropedImage];

    CGImageRelease(cropedImage);
    CGImageRelease(quartzImage);
    return (image);    
}

- (UIImage *)scaleAndRotateImage:(UIImage *)image withMaxWidth:(int)maxWitdh withImageOrientation:(UIImageOrientation)orientation
{
	int kMaxResolution = maxWitdh; //352; // Or whatever

	CGImageRef imgRef = image.CGImage;

	CGFloat width = CGImageGetWidth(imgRef);
	CGFloat height = CGImageGetHeight(imgRef);

	CGAffineTransform transform = CGAffineTransformIdentity;
	CGRect bounds = CGRectMake(0, 0, width, height);
	if (width > kMaxResolution || height > kMaxResolution) {
		CGFloat ratio = width/height;
		if (ratio > 1) {
			bounds.size.width = kMaxResolution;
			bounds.size.height = bounds.size.width / ratio;
		}
		else {
			bounds.size.height = kMaxResolution;
			bounds.size.width = bounds.size.height * ratio;
		}
	}

	CGFloat scaleRatio = bounds.size.width / width;
	CGSize imageSize = CGSizeMake(CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
	CGFloat boundHeight;
	UIImageOrientation orient = orientation; //image.imageOrientation;
	switch(orient) {

		case UIImageOrientationUp: //EXIF = 1
			transform = CGAffineTransformIdentity;
			break;
			
		case UIImageOrientationUpMirrored: //EXIF = 2
			transform = CGAffineTransformMakeTranslation(imageSize.width, 0.0);
			transform = CGAffineTransformScale(transform, -1.0, 1.0);
			break;
			
		case UIImageOrientationDown: //EXIF = 3
			transform = CGAffineTransformMakeTranslation(imageSize.width, imageSize.height);
			transform = CGAffineTransformRotate(transform, M_PI);
			break;
			
		case UIImageOrientationDownMirrored: //EXIF = 4
			transform = CGAffineTransformMakeTranslation(0.0, imageSize.height);
			transform = CGAffineTransformScale(transform, 1.0, -1.0);
			break;
			
		case UIImageOrientationLeftMirrored: //EXIF = 5
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeTranslation(imageSize.height, imageSize.width);
			transform = CGAffineTransformScale(transform, -1.0, 1.0);
			transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
			break;
			
		case UIImageOrientationLeft: //EXIF = 6
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeTranslation(0.0, imageSize.width);
			transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
			break;
			
		case UIImageOrientationRightMirrored: //EXIF = 7
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeScale(-1.0, 1.0);
			transform = CGAffineTransformRotate(transform, M_PI / 2.0);
			break;
			
		case UIImageOrientationRight: //EXIF = 8
			boundHeight = bounds.size.height;
			bounds.size.height = bounds.size.width;
			bounds.size.width = boundHeight;
			transform = CGAffineTransformMakeTranslation(imageSize.height, 0.0);
			transform = CGAffineTransformRotate(transform, M_PI / 2.0);
			break;
			
		default:
			[NSException raise:NSInternalInconsistencyException format:@"Invalid image orientation"];
             
             }
             
             UIGraphicsBeginImageContext(bounds.size);

             CGContextRef context = UIGraphicsGetCurrentContext();

             if (orient == UIImageOrientationRight || orient == UIImageOrientationLeft) {
                 CGContextScaleCTM(context, -scaleRatio, scaleRatio);
                 CGContextTranslateCTM(context, -height, 0);
             }
             else {
                 CGContextScaleCTM(context, scaleRatio, -scaleRatio);
                 CGContextTranslateCTM(context, 0, -height);
             }

             CGContextConcatCTM(context, transform);

             CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, width, height), imgRef);
             UIImage *imageCopy = UIGraphicsGetImageFromCurrentImageContext();

             UIGraphicsEndImageContext();

    return imageCopy;
}
             
@end
