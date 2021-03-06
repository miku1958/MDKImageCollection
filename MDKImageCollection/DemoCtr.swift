//
//  DemoCtr.swift
//  MDKImageCollection
//
//  Created by mikun on 2018/8/11.
//  Copyright © 2018年 mdk. All rights reserved.
//

import UIKit
import WebKit

class DemoCtr: UIViewController {

	var index:Int = 0
    override func viewDidLoad() {
        super.viewDidLoad()
		switch index {
		case 0:
			InfiniteTest()
		case 1:
			UpdateTest()
		case 2:
			gakkiTest(diff: false)
		case 3:
			gakkiTest(diff: true)
		case 4:
			QRCodeTest()
		case 5:
			webviewInside()
		default:
			break
		}
		if #available(iOS 11.0, *) {
			imageCollection?.contentInsetAdjustmentBehavior = .automatic
		}


    }
	

	var imageCollection:ImageCollectionView?
	func InfiniteTest() -> () {
		let flow = UICollectionViewFlowLayout()
		flow.itemSize = CGSize(width: 100, height: 100)
		imageCollection = ImageCollectionView(frame: CGRect(), flowLayout: flow)
		view.addSubview(imageCollection!)
		
		imageCollection?.thumbnailForIndexUseCheck(close: { (option, handler) in
			handler(UIImage(named: "\(option.index%3)"))
			return true
		}).largeForIndex { (option, handler) in
			handler(UIImage(named: "\(option.index%3)"))
		}
		imageCollection?.frame = CGRect(x: 0, y: 0, width: view.frame.size.width, height: view.frame.size.height)
	}
	func UpdateTest() -> () {
		let flow = UICollectionViewFlowLayout()
		flow.itemSize = CGSize(width: 100, height: 100)
		imageCollection = ImageCollectionView(frame: CGRect(), flowLayout: flow)
		view.addSubview(imageCollection!)
		
		imageCollection?.thumbnailForIndex(count: 40, close: { (option, handler) in
			handler(UIImage(named: "\(option.index%3)"))
			if option.index == 39{
				self.imageCollection?.updateCount(80)
			}
		}).largeForIndex { (option, handler) in
			handler(UIImage(named: "\(option.index%3)"))
		}
		imageCollection?.frame = CGRect(x: 0, y: 0, width: view.frame.size.width, height: view.frame.size.height)
	}
	func gakkiTest(diff:Bool) -> () {
		guard
			let path = Bundle.main.path(forResource: "gakki.plist", ofType: nil),
			let urlArr = NSArray(contentsOfFile: path) as? [String]
			else {return}
		
		let flow = UICollectionViewFlowLayout()
		flow.itemSize = CGSize(width: 100, height: 100)
		imageCollection = ImageCollectionView(frame: CGRect(), flowLayout: flow)
		view.addSubview(imageCollection!)
		imageCollection?.registerFor3DTouchPreviewing(self)
		imageCollection?.thumbnailForIndex(count: urlArr.count, close: { (option, handler) in
			var url = urlArr[option.index]
			if !diff{
				url = url.replacingOccurrences(of: "thumb300", with: "orj360")
			}
			self.downloadImage(url: url, finish: { (image) in
				handler(image)
			})
		}).largeForIndex { (option, handler) in
			let url = urlArr[option.index].replacingOccurrences(of: "thumb300", with: "large")
			print(url)
			self.downloadImage(url:url , finish: { (image) in
				handler(image)
			})
		}
		imageCollection?.frame = CGRect(x: 0, y: 0, width: view.frame.size.width, height: view.frame.size.height)
	}
	func QRCodeTest() -> () {
		imageCollection = ImageCollectionView()
		let layout = imageCollection?.collectionViewLayout as! UICollectionViewFlowLayout
		layout.itemSize = #imageLiteral(resourceName: "QRCode").size
		view.addSubview(imageCollection!)
		
		imageCollection?.thumbnailForIndex(count: 1, close: { (_, handler) in
			handler(#imageLiteral(resourceName: "QRCode"))
		}).largeForIndex { (option, handler) in
			handler(#imageLiteral(resourceName: "QRCode"))
		}
		imageCollection?.frame.size = #imageLiteral(resourceName: "QRCode").size
		imageCollection?.center.x = view.center.x
		imageCollection?.frame.origin.y = 100
	}
	func webviewInside() -> () {
		let webView = WKWebView(frame: view.bounds)
		view.addSubview(webView)
		if #available(iOS 11.0, *) {
			webView.scrollView.contentInsetAdjustmentBehavior = .always
		}
		webView.MDKImage.enableWhenClickImage {[weak self] (frame,imageURLArray,clickIndex)  in
			let display = MDKImageDisplayController(photoCount: imageURLArray.count, largeClose: {  (option, handler) in
				self?.downloadImage(url: imageURLArray[option.index], finish: { (image) in
					handler(image)
				})
			})
			display.disableBlurBackgroundWithBlack = true
			display.setDisplayIndex(clickIndex)
			if let nav = self?.navigationController{
				display.transition.sourceScreenInset = UIEdgeInsets(top: nav.navigationBar.frame.maxY, left: 0, bottom: 0, right: 0)
			}

			display.registerAppearSourecFrame({ () -> (CGRect) in
				return frame
			})
			display.registerDismissTargetFrame({ (option) -> (CGRect) in
				if option.index == clickIndex{
					return frame
				}
				return CGRect()
			})

			self?.present(display, animated: true, completion: nil)
		}
		webView.load(URLRequest(url: URL(string: "https://mp.weixin.qq.com/s/bY7JeNZAJekvnqvxsfSGxQ")!))
	}
	var cache:NSCache<NSString,UIImage> = NSCache()
	var downloaingList:[String:[(UIImage)->()]] = [:]
	func downloadImage(url urlstr:String , finish:@escaping (UIImage)->()) {
		if let image =  cache.object(forKey: urlstr as NSString) {
			finish(image)
			return
		}
		let path = "\(MDKFileTempWith("imageCache"))/\(urlstr.hash).png"
		
//		if let image = UIImage(contentsOfFile: path) {
//			finish(image)
//			cache.setObject(image, forKey: urlstr as NSString)
//			return
//		}
		
		if (downloaingList[urlstr] == nil) {
			downloaingList[urlstr] = [finish]
		}else{
			downloaingList[urlstr]?.append(finish)
			return
		}
		
		guard let url = URL(string: urlstr) else {return}
		
		URLSession.shared.dataTask(with: url) {[weak self] (data, _, _) in
			guard
				let data = data,
				let image = UIImage(data: data)
				else {return}
			self?.cache.setObject(image, forKey: urlstr as NSString)
			try? FileManager.default.createDirectory(atPath: MDKFileTempWith("imageCache"), withIntermediateDirectories: true, attributes: nil)
			try? UIImagePNGRepresentation(image)?.write(to: URL(fileURLWithPath: path))
			if let arr = self?.downloaingList[urlstr]{
				for finish in arr{
					finish(image)
				}
			}
			self?.downloaingList[urlstr] = nil
			}.resume()
	}
	


}
