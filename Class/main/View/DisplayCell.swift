//
//  DisplayCell.swift
//  MDKImageCollection
//
//  Created by mikun on 2018/7/14.
//  Copyright © 2018 mdk. All rights reserved.
//

import UIKit

protocol DisplayCellDelegate : NSObjectProtocol {
	func displayCell(_ cell:DisplayCell ,  scrollPanHandle pan:UIPanGestureRecognizer) -> ()
}

class DisplayCell: UICollectionViewCell,MDKImageProtocol {

	var updatingPhoto:Bool = false
	func setPhoto(_ photo:UIImage?,isThumbnail:Bool) -> () {
		guard let photo = photo else {return}
		updatingPhoto = true

		let size = photo.size
		if imageView.image == nil {
			imageView.image = photo
			contentScroll.zoomScale = 1
			imageView.sizeToFit()
			updateSize(size: size,resetOffset: true)
		}else if let image = imageView.image , image != photo{
			imageView.image = photo
			let ratio = size.width / size.height
			let lastRatio = self.imageView.frame.size.width / self.imageView.frame.size.height
			if fabs(ratio-lastRatio) > 0.01 {//防止两张图是因为缩小分辨率后比例稍微有些变化
				UIView.animate(withDuration: MDKImageTransition.duration, animations: {
					self.imageView.frame.size.height = self.imageView.frame.size.width / ratio
					self.imageView.frame.origin = CGPoint()
					self.scrollViewDidScroll(self.contentScroll)
					//FIXME:	iphoneX在UIView.animation中修改contentInset会导致offset错位,(scrollViewDidZoom中)
					self.scrollViewDidZoom(self.contentScroll)
				}) { (_) in
					self.contentScroll.zoomScale = 1
					self.imageView.frame.size = size
					self.updateSize(size: size,resetOffset: isThumbnail)
					self.isScrolling = false
					self.updatingPhoto = false
				}
			}else{
				self.contentScroll.zoomScale = 1
				imageView.sizeToFit()
				updateSize(size: size,resetOffset: isThumbnail)
			}
		}

		isScrolling = false
		updatingPhoto = false
	}

	func updateWidthScale (size:CGSize , resetOffset:Bool) -> () {

		fullWidthScale = MDKScreenWidth/size.width
		miniZoomScale = min(0.5, fullWidthScale)
		maxZoomScale = max(2, fullWidthScale)
	}

	func updateSize(size:CGSize , resetOffset:Bool) -> () {

		updateWidthScale(size: size,resetOffset: resetOffset)

		contentScroll.contentSize = size


		contentScroll.minimumZoomScale = miniZoomScale
		contentScroll.maximumZoomScale = maxZoomScale

		if contentScroll.zoomScale !=  fullWidthScale{
			contentScroll.setZoomScale(fullWidthScale, animated: false)
		}

		lastZoomScale = fullWidthScale

		if resetOffset {
			contentScroll.contentOffset = CGPoint()
		}
		stopScrollOffset = nil
		contentScroll.contentInset = UIEdgeInsets();

		scrollViewDidZoom(self.contentScroll)
	}

	var isScrolling:Bool = false
	var canScroll:Bool = true



	weak var delegate:(UIScrollViewDelegate & DisplayCellDelegate)?
	
	let imageView:UIImageView = {
		let view = UIImageView()
		view.contentMode = .scaleAspectFill
		view.clipsToBounds = true
		return view
	}()

	var stopScrollOffset:CGPoint? = nil


	override init(frame: CGRect) {
		super.init(frame: frame)
		
		addSubview(contentScroll)
		contentScroll.addSubview(imageView)
		
		contentScroll.delegate = self
	}

	override func layoutSubviews() {
		contentScroll.frame = self.bounds
	}

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	lazy var contentScroll:UIScrollView = {
		let scroll = UIScrollView()
		
		if #available(iOS 11.0, *) {
			scroll.contentInsetAdjustmentBehavior = .never
		}
		scroll.panGestureRecognizer.removeTarget(scroll, action: nil)
		scroll.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
		contentScrollPanSelector = NSSelectorFromString("handlePan:")
		return scroll
	}()
	
	
	var fullWidthScale:CGFloat = 0
	var miniZoomScale:CGFloat = 0
	var maxZoomScale:CGFloat = 0
	var lastZoomScale:CGFloat = 0
	func scale(finish:@escaping ()->()) -> () {
		imageView.layer.speed = 1

		UIView.animate(withDuration: 0.3, animations: {
			if self.fullWidthScale == self.miniZoomScale || self.fullWidthScale == self.maxZoomScale{
				if self.contentScroll.zoomScale != self.maxZoomScale{
					self.contentScroll.zoomScale = self.maxZoomScale
				}else{
					self.contentScroll.zoomScale = self.miniZoomScale
				}
				return
			}
			let lastScale = self.lastZoomScale
			self.lastZoomScale = self.contentScroll.zoomScale
			switch (lastScale,self.contentScroll.zoomScale) {

			case (self.fullWidthScale,self.fullWidthScale):
				self.contentScroll.zoomScale = self.maxZoomScale

			case (self.fullWidthScale,self.maxZoomScale):
				self.contentScroll.zoomScale = self.fullWidthScale

			case (self.maxZoomScale,self.fullWidthScale):
				self.contentScroll.zoomScale = self.miniZoomScale

			case (self.fullWidthScale,self.miniZoomScale):
				self.contentScroll.zoomScale = self.fullWidthScale

			case (self.miniZoomScale,self.fullWidthScale):
				self.contentScroll.zoomScale = self.maxZoomScale

			case (self.maxZoomScale,self.miniZoomScale):
				self.contentScroll.zoomScale = self.fullWidthScale

			case (self.miniZoomScale,self.maxZoomScale):
				self.contentScroll.zoomScale = self.fullWidthScale
				
			default:
				if self.contentScroll.zoomScale != self.maxZoomScale{
					self.contentScroll.zoomScale = self.maxZoomScale
				}else{
					self.contentScroll.zoomScale = self.miniZoomScale
				}
			}
		}) { (_) in
			finish()
		}
	}
	func makeScroll(stop:Bool) {
		isUserInteractionEnabled = !stop
		contentScroll.isScrollEnabled = !stop
		contentScroll.panGestureRecognizer.isEnabled = !stop
		if stop {
			stopScrollOffset = contentScroll.contentOffset
		}else{
			stopScrollOffset = nil
		}
	}
	
	
	var contentScrollPanSelector : Selector!
}


extension DisplayCell:UIScrollViewDelegate{
	@objc func handlePan(_ pan:UIPanGestureRecognizer) -> () {
		delegate?.displayCell(self, scrollPanHandle: pan)
		
		if canScroll {
			pan.view?.perform(contentScrollPanSelector, with: pan)
		}
	}
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		//fix : 极小概率下imageVIew的位置在连续pinch下会出错的问题
		imageView.frame.origin = CGPoint()
		//fix : pinch的时候设置图片会错位
		updatingPhoto = true
		scrollViewDidZoom(scrollView)
		return imageView
	}
	
	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		if !updatingPhoto {
			delegate?.scrollViewDidZoom?(scrollView)
		}

		contentScroll.contentInset = contentScrollInset

		scrollViewDidEndDecelerating(contentScroll)
	}

	var contentScrollInset : UIEdgeInsets{
		let showPicHeight = imageView.frame.size.height;
		let showPicWidth = imageView.frame.size.width;
		return UIEdgeInsetsMake(
			showPicHeight>=MDKScreenHeight ? 0 :
				(MDKScreenHeight-showPicHeight)/2,
			showPicWidth>=MDKScreenWidth ? 0 :
				(MDKScreenWidth-showPicWidth)/2,
			0,
			0
		)
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		if !updatingPhoto {
			delegate?.scrollViewDidScroll?(scrollView)
		}

		if scrollView == contentScroll{
			if let stopOffset = stopScrollOffset{
				contentScroll.setContentOffset(stopOffset, animated: false)
			}
			let trans = scrollView.panGestureRecognizer.translation(in: nil)
			isScrolling = fabs(trans.x) > 1 || fabs(trans.y) > 1 || scrollView.isZooming || scrollView.isDragging || scrollView.isDecelerating
		}
	}

	func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if !decelerate {
			scrollViewDidEndDecelerating(scrollView)
		}
	}
	func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
			self.isScrolling = false
		}
	}

	func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
		isScrolling = false
	}

	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		isScrolling = false
	}
}

