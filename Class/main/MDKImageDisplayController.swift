//
//  MDKImageDisplayController.swift
//  MDKImageCollection
//
//  Created by mikun on 2018/7/14.
//  Copyright © 2018 mdk. All rights reserved.
//

import UIKit

//TODO:	做读取时占位提示圈
//TODO:	dismiss的时候,如果不是同一张图片就做渐变
//FIXME:	图片比例不一样的时候,iphoneX会跳一下

open class MDKImageDisplayController: UIViewController {

	static private weak var instance:MDKImageDisplayController?
	
	@objc public class func current() -> MDKImageDisplayController? {
		return instance
	}

	private var largeClose:OptionImgClose?

	@objc public convenience init(photoCount:Int ,largeClose:OptionImgClose?) {
		
		self.init()
		
		photoList.count = photoCount
		self.largeClose = largeClose

//		setDisplayIndex(0)
	}

	private var largeIdentiferClose:OptionImgRtStringClose?
	private var leftmostIndex:Int?
	@objc public convenience init(largeClose:OptionImgRtStringClose?) {

		self.init()

		photoList.count = 1
		largeIdentiferClose = largeClose

//		setDisplayIndex(0)
	}
	
	required public init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		initself()
	}
	

	private init() {
		super.init(nibName: nil, bundle: nil)
		initself()
	}
	
	func initself() -> () {
		MDKImageDisplayController.instance = self
		modalPresentationStyle = .custom;
		transitioningDelegate = transition
		

		
		
		collectionView.addGestureRecognizer(dismissPan)
		dismissPan.addTarget(self, action: #selector(dismissPanFunc(pan:)))
		dismissPan.delegate = self
		
		collectionView.addGestureRecognizer(toolbarPan)
		toolbarPan.addTarget(self, action: #selector(toolbarPanFunc(pan:)))
		toolbarPan.delegate = self
		
		
		dismissTap.addTarget(self, action: #selector(tapDismissFunc(tap:)))
		collectionView.addGestureRecognizer(dismissTap)
		
		dismissTap.numberOfTapsRequired = 1
		dismissTap.numberOfTouchesRequired = 1
		dismissTap.delegate = self
		dismissTap.require(toFail: dismissPan)
		dismissTap.require(toFail: zoomTap)
		dismissTap.require(toFail: toolbarPan)
		
		zoomTap.addTarget(self, action: #selector(tapZoomFunc(tap:)))
		collectionView.addGestureRecognizer(zoomTap)
		
		
		zoomTap.delegate = self
		zoomTap.require(toFail: dismissPan)
		
		
		longPress.addTarget(self, action: #selector(longPressFunc(longPress:)))
		collectionView.addGestureRecognizer(longPress)
		longPress.delegate = self
		longPress.require(toFail: zoomTap)
		
		toolbar.addFinalAction { [weak self] in
			self?.dismissToolbar(finish: {})
		}
		savePhotoResult = { result in
			switch result {
			case .success:
				UIAlertController(title: "保存成功", message: nil, preferredStyle: .alert).MDKAdd(Cancel: { (_) in
					
				}, title: "返回").MDKQuickPresented()
			case .fail(.denied):
				fallthrough
			case .fail(.restricted):
				UIAlertController(title: "请允许 APP 访问图片", message: nil, preferredStyle: .alert).MDKAdd(Cancel: { (_) in
					
				}, title: "返回").MDKQuickPresented()
			case let .fail(.saveingFail(error)):
				UIAlertController(title: "保存失败", message: error.localizedDescription, preferredStyle: .alert).MDKAdd(Cancel: { (_) in
					
				}, title: "返回").MDKQuickPresented()
			}
		}
	}

	lazy var blurView = UIVisualEffectView(frame: MDKKeywindow.bounds)

	lazy var blackView:UIView = {
		let view = UIView(frame: MDKKeywindow.bounds)
		view.backgroundColor = .black
		view.alpha = 0
		return view
	}()
	
	lazy var collectionView:UICollectionView = {
		let flow = UICollectionViewFlowLayout()
		flow.minimumLineSpacing = 0
		flow.minimumInteritemSpacing = 0
		flow.itemSize = CGSize(width: MDKScreenWidth, height: MDKScreenHeight)//-1貌似是为了防止3D TOUCH出来的照片尺寸一样导致没有滚动到目标位置,但是-1的话visableCells就会有两个导致各种问题
		flow.scrollDirection = .horizontal
		let collection = UICollectionView(frame: CGRect(origin: CGPoint(), size: flow.itemSize), collectionViewLayout: flow)
		collection.backgroundColor = nil
		collection.isPagingEnabled = true
		collection.delegate = self
		collection.dataSource = self
		collection.MDKRegister(Cell: DisplayCell.self)

		collection.showsVerticalScrollIndicator = false
		collection.showsHorizontalScrollIndicator = false

		collection.panGestureRecognizer.removeTarget(collection, action: nil)
		collection.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
		collectionPanSelector = NSSelectorFromString("handlePan:")
		return collection
	}()
	var collectionPanSelector : Selector!
	var collectionPanBeginOffset:CGPoint = CGPoint()
	var collectionPanLastTranslation:CGPoint = CGPoint()

	var toolbar:toolbarView = toolbarView()

	var beginIndex:Int = 0
	@objc public func setDisplayIndex(_ displayIndex:Int) -> () {
		beginIndex = displayIndex
		collectionView.reloadData()
		let displayIndexPath = IndexPath(item: displayIndex, section: 0)
		collectionView.scrollToItem(at: displayIndexPath, at: .left, animated: false)
		collectionViewIsScrolling = false

		if largeIdentiferClose != nil {
			loadPhoto(displayIndex)
		}
		collectionView.layoutIfNeeded()


	}
	var displayIndex:Int{
		guard let visableCells = collectionView.visibleCells as? [DisplayCell] else { return 0}
		for cell in visableCells{
			if cell.imageView.image != nil , let indexPath = collectionView.indexPath(for: cell){
				return indexPath.item
			}
		}
		return 0
	}




	fileprivate var photoList:lazyArray<photoNode> = lazyArray(0, {(index)->(photoNode) in
		var photo = photoNode()
		photo.index = index
		return photo
	})
	var preloadCloses:[Int:Bool] = [:]



	var isFailToTryPrevious:Bool?
	var isFailToTryNext:Bool?


	public var isFrom3DTouch:Bool = false

	//MARK:	手势相关
	let dismissPan:UIPanGestureRecognizer = UIPanGestureRecognizer()

	let toolbarPan:UIPanGestureRecognizer = UIPanGestureRecognizer()
	var toolbarPanLastTranslation:CGPoint = CGPoint()

	let longPress = UILongPressGestureRecognizer()

	let dismissTap:UITapGestureRecognizer = UITapGestureRecognizer()
	let zoomTap:DoubleTapThanPanGesture = DoubleTapThanPanGesture()
	var tapCount:Int = 0


	var toolbarIsOpening:Bool = false
	var toolbarIsFinishOpen:Bool = false
	
	var longPressIsActive:Bool = false
	
	

	var savePhotoResult : SavePhotoClose?
	@objc var savePhotoResultObjc : SavePhotoBlock?

	var collectionViewIsScrolling :Bool = false
	
	@objc public let transition = MDKImageTransition.global()

	///transition 动画是否做完
	var didFinishPresentTransitionAnimation:Bool = false
	var shouldResetCellImage:Bool = false
	///transition 动画做做完后需不需要切换到大图(防止layer动画的时候切换大图会导致视图大小出错)
	var needSwitchToLarge:Bool = true

	
	var _animator:AnyObject?
	@available(iOS 10.0, *)
	func animator() -> UIViewPropertyAnimator? {
		return _animator as? UIViewPropertyAnimator
	}

	
	///用来第一次显示的时候滚动到当前要显示的cell
	var firstResetPosition :Bool = false

	
//MARK:	供外部使用的属性
	@objc public  var displayIndexWillChange:IndexClose?
	@objc public  var willDismiss:IndexClose?
	@objc public  var didDismiss:IndexClose?
	///供外部获取当前displayCtr的显示信息
	@objc public var displayingInfo:MDKImageDisplayingInfo{
		let option = MDKImageDisplayingInfo()
		let pNode = photoList[displayIndex - photoList.negativeCount]
		if pNode.isDequeueFromIdentifier,let identifier = pNode.identifier{
			option.identifier = identifier
		}else{
			option.index = displayIndex
		}
		return option
	}
	public var QRCodeHandler:QRCodeHandlerClose = { QRCodes,touchPoint in
		if QRCodes.count == 1{
			UIApplication.shared.openURL(MDKURL(QRCodes.first!.key))
		}else{
			var inPoint = false
			if var touchPoint = touchPoint{
				for (message,rect) in QRCodes {
					
					if rect.contains(touchPoint){
						inPoint = true
						UIApplication.shared.openURL(MDKURL(message))
						break
					}
				}
			}
			if !inPoint{
				//弹个选择框给用户
				let alert = UIAlertController(title: "检查到多个二维码", message: "请选择", preferredStyle: .actionSheet)
				for (message,_) in QRCodes {
					alert.MDKAdd(Default: { (action) in
						UIApplication.shared.openURL(MDKURL(message))
					}, title: message)
				}
				alert.MDKAdd(Cancel: { (action) in
					
				}, title: "取消")
				alert.MDKQuickPresented()
			}
		}
	}

	@objc public var registerAppearSourecView:RegisterAppearViewClose?
	func registerAppearSourecView(_ register:@escaping RegisterAppearViewClose) -> () {
		registerAppearSourecView = register
	}
	
	@objc public var registerDismissTargetView:RegisterDismissViewClose?
	func registerDismissTargetView(_ register:@escaping RegisterDismissViewClose) -> () {
		registerDismissTargetView = register
	}

	@objc public var registerAppearSourecFrame:RegisterAppearKeyWinFrameClose?
	func registerAppearSourecFrame(_ register:@escaping RegisterAppearKeyWinFrameClose) -> () {
		registerAppearSourecFrame = register
	}

	@objc public var registerDismissTargetFrame:RegisterDismissKeyWinFrameClose?
	func registerDismissTargetFrame(_ register:@escaping RegisterDismissKeyWinFrameClose) -> () {
		registerDismissTargetFrame = register
	}
	
	@objc public var disableBlurBackgroundWithBlack:Bool = false

	var didLoadAnyImage:Bool = false
}



//MARK:	view function
extension MDKImageDisplayController{
	
	override open func viewDidLoad() {
		super.viewDidLoad()
		if disableBlurBackgroundWithBlack {
			view.addSubview(blackView)
		}else{
			view.addSubview(blurView)
		}
		view.addSubview(collectionView)
	}
	
	override open func viewDidLayoutSubviews() {
		let collFrame = collectionView.frame
		
		if collFrame.size != view.bounds.size {
			collectionView.frame = view.bounds
			if disableBlurBackgroundWithBlack{
				blackView.frame = collectionView.frame
			}else{
				blurView.frame = collectionView.frame
			}
			if !firstResetPosition{
				firstResetPosition = true
				
				self.collectionView.scrollToItem(at: IndexPath(item: beginIndex + self.photoList.negativeCount, section: 0), at: .left, animated: false)
				self.collectionViewIsScrolling = false
			}
			
		}
		
	}
	
	override open func viewWillAppear(_ animated: Bool) {
		if largeIdentiferClose != nil ,photoList[0].identifier == nil{
			setDisplayIndex(0)
		}
		if let sourceView = registerAppearSourecView?(){
			MDKImageTransition.global().beginViewMap.add(sourceView)
		}else if let sourceFrame = registerAppearSourecFrame?(){
			MDKImageTransition.global().beginSourceFrame = sourceFrame
		}

		if let cell = collectionView.visibleCells.first as? DisplayCell{
			MDKImageTransition.global().beginViewMap.add(cell.imageView)
		}

		UIView.animate(withDuration: MDKImageTransition.duration) {
			if self.disableBlurBackgroundWithBlack{
				self.blackView.alpha = 1
			}else{
				self.blurView.effect = UIBlurEffect(style: .dark)
			}
		}
		
		dismissToolbar { }
	}
	override open func viewDidAppear(_ animated: Bool) {
		if didFinishPresentTransitionAnimation && isFrom3DTouch {
			didFinishPresent(true)
		}
		didFinishPresentTransitionAnimation = true
		if let cell = collectionView.visibleCells.first as? DisplayCell{
			cell.isScrolling = false
			MDKImageTransition.global().beginViewMap.remove(cell.imageView)
		}
	}
	func didFinishPresent(_ animated: Bool) -> () {
		didFinishPresentTransitionAnimation = true
		collectionViewIsScrolling = false
		if needSwitchToLarge , displayIndex-photoList.negativeCount == beginIndex, let cell = collectionView.visibleCells.first , let indexPath = collectionView.indexPath(for: cell){
			collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)
		}
	}
	
	override open func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		updateDismissView()
		updateDismissAnimator()
	}
	func updateDismissView() -> () {
		let option = MDKImageCloseOption()
		option.index = displayIndex
		option.lastIdentifier = photoList[displayIndex - photoList.negativeCount].identifier
		MDKImageTransition.global().dismissViewMap.removeAllObjects()
		if let sourceView = registerDismissTargetView?(option) {
			MDKImageTransition.global().dismissViewMap.add(sourceView)
		}else if let targetFrame = registerDismissTargetFrame?(option) , targetFrame != CGRect(){
			MDKImageTransition.global().dismissTargetFrame = targetFrame
		}
		if let cell = collectionView.visibleCells.first as? DisplayCell{
			MDKImageTransition.global().dismissViewMap.add(cell.imageView)
		}
	}

	func updateDismissAnimator() -> () {
		if #available(iOS 10.0, *) {
			let anim = UIViewPropertyAnimator(duration: MDKImageTransition.duration, curve: .easeInOut) {
				if self.disableBlurBackgroundWithBlack{
					self.blackView.alpha = 0
				}else{
					self.blurView.effect = nil
				}
			}
			anim.addCompletion { (position) in
				switch position {
				case .start , .end:
					self._animator = nil
				default:break
				}
			}
			anim.startAnimation()
			_animator = anim
		} else {
			UIView.animate(withDuration: 0.15) {
				if self.disableBlurBackgroundWithBlack{
					self.blackView.alpha = 0
				}else{
					self.blurView.effect = nil
				}
			}
		}
	}
}

//MARK:	UICollectionViewDelegate,UICollectionViewDataSource
extension MDKImageDisplayController: UICollectionViewDelegateFlowLayout,UICollectionViewDataSource{
	public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return photoList.count + photoList.negativeCount
	}

	public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NSStringFromClass(DisplayCell.self), for: indexPath) as! DisplayCell
		if cell.delegate == nil {
			cell.delegate = self
			if let pinch = cell.contentScroll.pinchGestureRecognizer{
				longPress.require(toFail:pinch)
				toolbarPan.require(toFail: pinch)
			}

		}
		return cell
	}
	public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {

		let item = indexPath.item
		let displayIndex = item - photoList.negativeCount

		displayIndexWillChange?(displayIndex)
		guard let cell = cell as? DisplayCell else { return }
		cell.imageView.alpha = 1
		cell.imageView.layer.mask = nil
		cell.isScrolling = false
		if shouldResetCellImage{
			cell.imageView.image = nil
		}
		if let photo = photoList[displayIndex].photo {
			updateCell(cell, image: photo, displayIndex: displayIndex, isThumbnail: photoList[displayIndex].photoQuality == .thumbnail)
		}


		if let leftmostIndex = leftmostIndex, indexPath.item == leftmostIndex{
			return
		}


		let option = MDKImageCloseOption()
		if displayIndex>0 {
			option.lastIdentifier = photoList[displayIndex-1].identifier
		}else if displayIndex<0{
			option.lastIdentifier = photoList[displayIndex+1].identifier
		}
		option.index = displayIndex
		option.needQuality = .large
		option.displayCtr = self
		var hasLargePhoto = false
		var largeIsFromNet = false//修正加载大图太快会闪一下
		let handler:(UIImage?)->() = {[weak self] photo in
			if let _self = self , ( !largeIsFromNet ||  _self.didFinishPresentTransitionAnimation){

				if displayIndex == 0{
					_self.needSwitchToLarge = false
				}
				hasLargePhoto = true
				guard let photo = photo else {return}
				_self.photoList[displayIndex].photoQuality = .large
				_self.photoList[displayIndex].photo = photo

				DispatchQueue.main.async(execute: {
					if let cell = _self.collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? DisplayCell {

						_self.updateCell(cell, image: photo, displayIndex: displayIndex, isThumbnail: false)
						_self.shouldResetCellImage = true

					}
				})

			}
		}
		largeClose?(option,handler)
		let _ = largeIdentiferClose?(option,handler)

		largeIsFromNet = true


		if !hasLargePhoto {
			option.needQuality = .thumbnail
			let handler:(UIImage?) -> () = {[weak self] photo  in
				DispatchQueue.main.async {
					guard let _self = self else {return}
					if _self.photoList[displayIndex].photoQuality == .thumbnail{
						_self.photoList[displayIndex].photo = photo
						if let cell = _self.collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? DisplayCell{
							_self.updateCell(cell, image: photo, displayIndex: displayIndex, isThumbnail: true)
						}
					}
				}
			}
			largeClose?(option,handler)
			let _ = largeIdentiferClose?(option,handler)
		}
		MDKImageTransition.syncQueue.async {
			DispatchQueue.main.sync {
				MDKImageTransition.synchronized({
					self.loadPhoto(displayIndex - 1)
					self.loadPhoto(displayIndex + 1)
				})
			}
		}
	}

	func updateCell(_ cell:DisplayCell , image:UIImage? , displayIndex:Int , isThumbnail:Bool) -> () {
		if transition.isInTransition , cell.imageView.image != nil{
			needSwitchToLarge = true
			return
		}
		needSwitchToLarge = false
		photoList[displayIndex].updatingCell = true
		cell.setPhoto(image, isThumbnail: isThumbnail)
		if let zoom = photoList[displayIndex].browsingScale{
			cell.contentScroll.zoomScale = zoom
		}
		if let offset = photoList[displayIndex].browsingOffset{
			cell.contentScroll.contentOffset = offset
		}

		photoList[displayIndex].updatingCell = false
	}
	public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		if didFinishPresentTransitionAnimation {
			 shouldResetCellImage = true
		}
		if let cell = cell as? DisplayCell {
			cell.isScrolling = false
		}
	}


	public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		collectionViewIsScrolling = true
	}
	public func scrollViewDidZoom(_ scrollView: UIScrollView) {
		if let cell = collectionView.visibleCells.first as? DisplayCell , scrollView == cell.contentScroll ,!photoList[displayIndex - photoList.negativeCount].updatingCell{
			photoList[displayIndex - photoList.negativeCount].browsingScale = scrollView.zoomScale
		}
	}
	@objc func handlePan(_ pan:UIPanGestureRecognizer) -> () {
		if pan.state == .began {
			collectionPanBeginOffset = collectionView.contentOffset
		}
		if let leftmostIndex = leftmostIndex,Int(collectionView.contentOffset.x / collectionView.frame.width) <= leftmostIndex {
			var translation = pan.translation(in: nil)

			let canPanWidth = collectionView.frame.width * 0.5
			let leftmostOffset = (CGFloat(leftmostIndex) + 1) * collectionView.frame.width - canPanWidth
			switch pan.state {
			case .ended:
				if collectionView.contentOffset.x - leftmostOffset < canPanWidth{
					pan.setTranslation(CGPoint(), in: nil)
					collectionView.setContentOffset(CGPoint(x: (CGFloat(leftmostIndex) + 1) * collectionView.frame.width, y: 0), animated: true)
					return
				}
			default:
				if collectionView.contentOffset.x - leftmostOffset < canPanWidth{
					let canPanTranslation = collectionPanBeginOffset.x - leftmostOffset
					if translation.x > canPanTranslation{
						pan.setTranslation(CGPoint(x: canPanTranslation, y: collectionPanBeginOffset.y), in: nil)
					}else{
						let transoffset = (translation.x - collectionPanLastTranslation.x) * (1-min(translation.x/canPanTranslation, 1))
						translation.x = collectionPanLastTranslation.x + transoffset * 0.6

						pan.setTranslation(translation, in: nil)
					}
				}

			}
			collectionPanLastTranslation = translation
		}

		collectionView.perform(collectionPanSelector, with: pan)
	}
	public func scrollViewDidScroll(_ scrollView: UIScrollView) {
		if scrollView.panGestureRecognizer.translation(in: nil).x > 1 || scrollView.panGestureRecognizer.translation(in: nil).y > 1 {
			resetTapCount()
		}

		if let cell = collectionView.visibleCells.first as? DisplayCell , scrollView == cell.contentScroll {
			if !photoList[displayIndex - photoList.negativeCount].updatingCell{
				photoList[displayIndex - photoList.negativeCount].browsingOffset = scrollView.contentOffset
			}
			if toolbarIsOpening ,scrollView.panGestureRecognizer.velocity(in: scrollView).y > 0{
				dismissToolbar(finish: {})
			}
		}
		if scrollView == collectionView {
			let trans = scrollView.panGestureRecognizer.translation(in: nil)
			collectionViewIsScrolling = fabs(trans.x) > 1 || fabs(trans.y) > 1 || scrollView.isZooming || scrollView.isDragging || scrollView.isDecelerating
		}
	}

	public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if !decelerate {
			scrollViewDidEndDecelerating(scrollView)
		}
	}
	public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		DispatchQueue.main.asyncAfter(deadline: .now()+0.15) {
			self.collectionViewIsScrolling = false
		}
	}

	public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
		collectionViewIsScrolling = false
	}



}

//MARK:	baseFunction
extension MDKImageDisplayController{
	
	func dismissWithAnimation(all:Bool = false) -> () {
		if !all {
			if toolbarIsFinishOpen {
				dismissToolbar(finish: {})
				return
			}
			if toolbarIsOpening {
				return
			}
		}

		willDismiss?(displayIndex)
		self.dismiss(animated: true, completion: {
			self.didDismiss?(self.displayIndex)
		})
	}

	func loadPhoto(_ displayIndex:Int)->()  {


		let option = MDKImageCloseOption()

		option.index = displayIndex
		option.needQuality = .large
		option.displayCtr = self


		var hasLargePhoto:Bool = false
		if let largeIdentiferClose = largeIdentiferClose{
			guard let _hasLarge = load(largeIdentiferClose: largeIdentiferClose, option: option, displayIndex: displayIndex) else{
				return
			}
			hasLargePhoto = _hasLarge
		}

		if let largeClose = largeClose{
			guard let _hasLarge = load(largeClose: largeClose, option: option, displayIndex: displayIndex) else{ return }
			hasLargePhoto = _hasLarge
		}


		if hasLargePhoto {
			return
		}
		option.needQuality = .thumbnail
		let handler:(UIImage?)->() = {[weak self] image  in
			DispatchQueue.main.async {
				guard let _self = self else {return}
				if _self.photoList[displayIndex].photoQuality == .thumbnail{

					_self.photoList[displayIndex].photo = image
				}
			}
		}
		largeClose?(option,handler)
		let _ = largeIdentiferClose?(option,handler)
	}
	func load(largeIdentiferClose:OptionImgRtStringClose , option:MDKImageCloseOption  ,displayIndex:Int) -> (Bool?) {


		let maxNegativeIndex = (-photoList.negativeCount) - 1;
		guard displayIndex >= maxNegativeIndex , displayIndex <= photoList.count else { return nil}
		let isTryingNext = displayIndex == photoList.count
		let isTryingPrevious = displayIndex == maxNegativeIndex
		if isTryingNext ,(isFailToTryNext ?? false ||
			photoList[displayIndex-1].identifier == nil){

			return nil
		}
		if isTryingPrevious , (isFailToTryPrevious ?? false ||
			photoList[displayIndex+1].identifier == nil){

			return nil
		}
		var inPreload = false
		if let _inPreload  = self.preloadCloses[displayIndex] {
			inPreload = _inPreload
		}
		guard !inPreload else { return nil}
		self.preloadCloses[displayIndex] = true

		if displayIndex>0 {
			option.lastIdentifier = photoList[displayIndex-1].identifier
		}else if displayIndex<0{
			option.lastIdentifier = photoList[displayIndex+1].identifier
		}


		var hasLargePhoto = false

		var cachePhotoNode:photoNode?

		var isFromInternet:Bool = false
		let identifier = largeIdentiferClose(option){[weak self] image  in
			hasLargePhoto = true
			cachePhotoNode = self?.update(image: image, cachePhotoNode: cachePhotoNode, isFromInternet: isFromInternet, displayIndex: displayIndex, isTryingNext: isTryingNext, isTryingPrevious: isTryingPrevious)
		}
		isFromInternet = true
		if identifier != nil {
			if isTryingNext {
				if photoList[displayIndex-1].identifier == identifier{
					return nil
				}
				self.photoList.count = max(self.photoList.count, displayIndex + 1)
				isFailToTryNext = false
				if cachePhotoNode != nil{
					self.photoList[displayIndex] = cachePhotoNode!
				}
				UIView.performWithoutAnimation {
					CATransaction.begin()
					CATransaction.setDisableActions(true)

					self.collectionView.insertItems(at: [IndexPath(item: displayIndex+self.photoList.negativeCount, section: 0)])

					CATransaction.commit()
				}


			}
			if isTryingPrevious {
				if photoList[displayIndex+1].identifier == identifier{
					return nil
				}
				photoList.negativeCount = (-displayIndex)
				if cachePhotoNode != nil{
					photoList[displayIndex] = cachePhotoNode!
				}
				isFailToTryPrevious = false
			}
			if identifier != nil {
				photoList[displayIndex].identifier = identifier
			}
			photoList[displayIndex].isDequeueFromIdentifier = true
			if (isTryingPrevious){

				let preloadCount = 1000


				let addOffset = self.collectionView.frame.width * CGFloat(preloadCount);
				let offsetX = self.collectionView.contentOffset.x + addOffset

				self.photoList.negativeCount += preloadCount-1
				UIView.performWithoutAnimation {
					CATransaction.begin()
					CATransaction.setDisableActions(true)

					self.collectionView.reloadData()


					self.collectionView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: false)



					CATransaction.commit()
				}
				self.collectionView.layoutIfNeeded()


				self.collectionViewIsScrolling = false
				for cell in self.collectionView.visibleCells as! [DisplayCell]{
					cell.isScrolling = false
				}

			}
		}else if isTryingNext{
			isFailToTryNext = true
			return nil
		}else if isTryingPrevious{
			isFailToTryPrevious = true
			return nil
		}
		if (identifier == nil  || option.lastIdentifier == nil) , displayIndex<0 , leftmostIndex==nil {
			leftmostIndex = displayIndex + photoList.negativeCount
		}

		return hasLargePhoto
	}

	func load(largeClose:OptionImgClose , option:MDKImageCloseOption  ,displayIndex:Int) -> (Bool?) {
		if displayIndex<0 || displayIndex>=photoList.count {
			return nil
		}
		var inPreload = false
		if let _inPreload  = self.preloadCloses[displayIndex] {
			inPreload = _inPreload
		}
		guard !inPreload else { return nil}
		self.preloadCloses[displayIndex] = true

		var hasLargePhoto = false

		var isFromInternet:Bool = false
		largeClose(option){[weak self] image in
			hasLargePhoto = true
			self?.update(image: image, cachePhotoNode: nil, isFromInternet: isFromInternet, displayIndex: displayIndex, isTryingNext: false, isTryingPrevious: false)
		}
		isFromInternet = true
		return hasLargePhoto
	}
	@discardableResult
	func update(image:UIImage? , cachePhotoNode:photoNode? ,isFromInternet:Bool,displayIndex:Int,isTryingNext:Bool,isTryingPrevious:Bool) -> (photoNode?) {
		var cachePhotoNode = cachePhotoNode
		DispatchQueue.main.async {[weak self] in
			guard let _self = self else{return}

			var pNode = photoNode()
			if _self.photoList.checkIndex(displayIndex){
				pNode = _self.photoList[displayIndex]
			}
			pNode.photoQuality = .large
			pNode.photo = image
			pNode.index = displayIndex
			if isTryingNext , displayIndex == _self.photoList.count{
				cachePhotoNode = pNode
			}else if isTryingPrevious, displayIndex == (-_self.photoList.negativeCount) - 1{
				cachePhotoNode = pNode
			}else{
				_self.photoList[displayIndex] = pNode
			}
			if let cell = _self.collectionView.cellForItem(at: IndexPath(item: displayIndex + _self.photoList.negativeCount, section: 0)) as? DisplayCell{

				_self.updateCell(cell, image: image, displayIndex: displayIndex, isThumbnail: false)
				self?.didLoadAnyImage = true
			}

		}
		return cachePhotoNode
	}
	func updatePhotoCount(_ count:Int) {
		var indexPaths:[IndexPath] = []
		for idx in photoList.count ..< count {
			indexPaths.append(IndexPath(item: idx, section: 0))
		}
		photoList.count = count
		UIView.performWithoutAnimation {
			CATransaction.begin()
			CATransaction.setDisableActions(true)

			self.collectionView.insertItems(at: indexPaths)

			CATransaction.commit()
		}
	}
	func resetToolbar(touchPoint:CGPoint? , cell:DisplayCell) -> () {
		toolbar
		.removeAllAction()
		.addGroup()
			.addAction(title: "保存图片", action: { [weak self] in
				self?.savePhoto()
			})
		.addGroup()
			.addAction(title: "关闭图片", action: {[weak self] in
				self?.dismissWithAnimation(all: true)
			})
			.addAction(title: "取消", action: { //[weak self] in

			})
		guard
			let indexPath = collectionView.indexPath(for: cell)
		else { return }
		
		DispatchQueue.global().async {
			self.photoList[indexPath.item - self.photoList.negativeCount].checkHasQRCode {
				DispatchQueue.main.async { [weak self] in
					if let _self = self , (_self.photoList[indexPath.item - _self.photoList.negativeCount].QRCode?.count ?? 0) > 0 {
						_self.toolbar.insertAction(title: "识别图中的二维码", action: {
							guard  let _self = self else {return}
							var convertPoint = touchPoint
							if convertPoint != nil{
								convertPoint = cell.imageView.convert(touchPoint!, from: cell)
								convertPoint!.x *= cell.imageView.image?.scale ?? 1
								convertPoint!.y *= cell.imageView.image?.scale ?? 1
							}
							_self.QRCodeHandler((_self.photoList[indexPath.item - _self.photoList.negativeCount].QRCode)!,convertPoint)
							}, atGroup: 0, at: 1)

						_self.changeToolBarPosition(offset: 0,forceAnimation: true)
					}
				}
			}
		}

		if toolbar.superview == nil {
			toolbar.frame.origin.y = view.frame.height
			view.addSubview(toolbar)
		}
	}
	func displayToolbar(_ touchPoint:CGPoint? = nil) -> () {
		
		guard
			let cell = collectionView.visibleCells.first as? DisplayCell
		else { return }



		resetToolbar(touchPoint: touchPoint, cell: cell)

		
		changeToolBarPosition(offset: -view.frame.height,forceAnimation: true)


		cell.makeScroll(stop: true)
		collectionView.isScrollEnabled = false

	}
	func dismissToolbar(finish:@escaping ()->()) -> () {


		collectionView.isScrollEnabled = true
		changeToolBarPosition(offset: view.frame.height, forceAnimation: true, finish: finish)
	}
	func changeToolBarPosition(offset:CGFloat ,forceAnimation:Bool = false , finish:(()->())? = nil , velocity _velocity:CGFloat? = nil) -> () {

		guard
			toolbar.actionList.count > 0,
			let cell = collectionView.visibleCells.first as? DisplayCell
		else { return }
		
		self.toolbarIsOpening = true
		self.toolbarIsFinishOpen = false
		var velocity:CGFloat = 0
		if _velocity != nil {
			velocity = _velocity!
		}

		UIView.animate(
			withDuration: forceAnimation ? MDKImageTransition.duration : 0,
			delay: 0,
			usingSpringWithDamping: velocity >= 0 ? 1 : 0.7,
			initialSpringVelocity: min(100, fabs(velocity)),
			options: .curveEaseOut,
			animations: {
			self.toolbar.frame.origin.y += offset

			if self.toolbar.frame.origin.y <= self.view.frame.height - self.toolbar.frame.height {
				self.toolbar.frame.origin.y = self.view.frame.height - self.toolbar.frame.height
			}else if self.toolbar.frame.origin.y >= self.view.frame.height {
				self.toolbar.frame.origin.y = self.view.frame.height
			}

			let photoBottom = max(-10, cell.frame.height - cell.imageView.superview!.convert(cell.imageView.frame, to: cell).maxY)
			if photoBottom <= (self.view.frame.height - self.toolbar.frame.origin.y){
				self.collectionView.frame.origin.y = 0-(self.view.frame.height - self.toolbar.frame.origin.y - photoBottom)
			}else{
				self.collectionView.frame.origin.y = 0
			}
		}) { (_) in
			finish?()
			self.resetTapCount()
			if self.toolbar.frame.origin.y <= self.view.frame.height - self.toolbar.frame.height {
				self.toolbarIsOpening = true
				self.toolbarIsFinishOpen = true
			}else if self.toolbar.frame.origin.y >= self.view.frame.height {
				self.toolbarIsOpening = false
				self.toolbarIsFinishOpen = false
				cell.canScroll = true
			}
		}

	}
}

//MARK:	GestureFunction
extension MDKImageDisplayController{
	@objc func dismissPanFunc(pan:UIPanGestureRecognizer) ->(){
		let translation = pan.translation(in: nil)

		let progress = min(fabs(translation.y / collectionView.bounds.height),  0.5)

		MDKImageTransition.global().process = progress
		guard let cell = collectionView.visibleCells.first as? DisplayCell else{return}
		switch pan.state {
		case .began:
			cell.contentScroll.panGestureRecognizer.isEnabled = false
			if #available(iOS 10.0, *) {
				updateDismissView()
				if animator() == nil {
					updateDismissAnimator()
				}else{
					animator()?.isReversed = false
				}
				animator()?.pauseAnimation()
			}else{
				viewWillDisappear(true)
			}
			MDKImageTransition.global().dismiss(viewController: self)
		case .changed:
			MDKImageTransition.global().process = progress
			if #available(iOS 10.0, *) {
				animator()?.fractionComplete = min(1, progress*1.5)
			}
			MDKImageTransition.global().controlTransitionView(position: translation)
		default:
			cell.contentScroll.panGestureRecognizer.isEnabled = true
			
			if progress + pan.velocity(in: nil).y / collectionView.bounds.height > 0.3 , translation.y > collectionView.bounds.height/4 {
				MDKImageTransition.global().commitDismiss()
				didDismiss?(displayIndex)
				forceFinishBlurViewDismissAnimation(isReversed: false)
			} else {
				MDKImageTransition.global().cancelDismiss()
				didDismiss?(displayIndex)
				forceFinishBlurViewDismissAnimation(isReversed: true)
			}
		}
	}
	func forceFinishBlurViewDismissAnimation(isReversed:Bool) -> () {
		if #available(iOS 10.0, *) {
			if let animator = animator(){
				var durationFactor : CGFloat = 1
				animator.isReversed = isReversed
				if isReversed {
					durationFactor = 1/animator.fractionComplete
				}else{
					durationFactor = 1/(1-animator.fractionComplete)
				}

				if durationFactor == .infinity {
					durationFactor = 1
				}
				animator.continueAnimation(withTimingParameters: UICubicTimingParameters(animationCurve: .easeIn), durationFactor:durationFactor)
			}
		}
	}
	@objc func toolbarPanFunc(pan:UIPanGestureRecognizer) ->(){

		if let cell = collectionView.visibleCells.first as? DisplayCell{
			cell.canScroll = false
		}
		let velocity = pan.velocity(in: nil)
		switch pan.state {
		case .began:
			if toolbarIsFinishOpen{
				if velocity.y<0 {
//					return;
				}
			}else{
				if velocity.y<0{
					if let cell = collectionView.visibleCells.first as? DisplayCell {
						resetToolbar(touchPoint: nil, cell: cell)
					}
				}
			}
		case .ended:
			if let cell = collectionView.visibleCells.first as? DisplayCell{
				cell.canScroll = true
			}

			toolbarPanLastTranslation = CGPoint()
			if toolbar.frame.origin.y < view.frame.height - toolbar.frame.height*2/3{
				changeToolBarPosition(offset: -view.frame.height,forceAnimation: true , velocity:velocity.y/200)
			}else if toolbar.frame.origin.y > view.frame.height - toolbar.frame.height*1/3{
				changeToolBarPosition(offset: view.frame.height,forceAnimation: true , velocity:velocity.y/200)
			}else if velocity.y<0{
				changeToolBarPosition(offset: -view.frame.height,forceAnimation: true , velocity:velocity.y/200)
			}else{
				changeToolBarPosition(offset: view.frame.height,forceAnimation: true , velocity:velocity.y/200)
			}
		default:
			let translation = pan.translation(in: nil)
			var offset = translation.y - toolbarPanLastTranslation.y;
			let maxOffset:CGFloat = 20
			offset = max(min(offset, maxOffset), -maxOffset)
			changeToolBarPosition(offset: offset)
			toolbarPanLastTranslation = translation;
		}
	}

	@objc func longPressFunc(longPress:UILongPressGestureRecognizer) -> (){
		switch longPress.state {
		case .began:
			longPressIsActive = true
			displayToolbar(longPress.location(in: nil))
		case .ended:
			DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(0.1)) {
				self.longPressIsActive = false
			}
		default: break
		}
	}
	func resetTapCount() {
		tapCount = 0
	}

	@objc fileprivate func tapDismissFunc(tap:UITapGestureRecognizer){
		if zoomTap.state == .failed && !longPressIsActive{
			tapCount = 1
			self.dismissWithAnimation()
		}
	}

	@objc fileprivate func tapZoomFunc(tap:DoubleTapThanPanGesture){

		if tap.didMoving {
			doubleTapThanPanFunc(pan: tap)
		}else{
			if toolbarIsFinishOpen {
				dismissToolbar(finish: {
					self.resetTapCount()
				})
			}else if !toolbarIsOpening{
				(collectionView.visibleCells.first as? DisplayCell)?.scale(finish: {
					self.resetTapCount()
				})
			}
		}

	}

	@objc func doubleTapThanPanFunc(pan:DoubleTapThanPanGesture){
		guard let cell = self.collectionView.visibleCells.first as? DisplayCell else { return }
		if collectionViewIsScrolling {
			cell.isScrolling = false
			return
		}
		if toolbarIsOpening || toolbarIsFinishOpen {
			return
		}
		switch pan.state {
		case .began:
			break
		case .ended:
			cell.isScrolling = false
		default:
			break
		}
		let translation = pan.translation(in: pan.view)

		var scale:CGFloat = 0

		scale = -translation.y
		scale /= 100
		if let contentScroll = (collectionView.visibleCells.first as? DisplayCell)?.contentScroll{
			contentScroll.setZoomScale(contentScroll.zoomScale + scale, animated: false)
		}

		pan.setTranslation(CGPoint(), in: pan.view)
	}
}

//MARK:	UIGestureRecognizerDelegate
extension MDKImageDisplayController:UIGestureRecognizerDelegate {
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {

		if gestureRecognizer == collectionView.panGestureRecognizer || otherGestureRecognizer == collectionView.panGestureRecognizer {
			return false
		}
		if otherGestureRecognizer.isKind(of: UIPinchGestureRecognizer.self){//UIScrollViewPinchGestureRecognizer
			return false
		}

		return true
	}
	public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {

		if gestureRecognizer == dismissTap || gestureRecognizer == zoomTap{
			guard let cell = self.collectionView.visibleCells.first as? DisplayCell else {return true}

			return ((!collectionViewIsScrolling && !cell.isScrolling) || toolbarIsFinishOpen) && _animator == nil
		}
		if gestureRecognizer.isKind(of: UILongPressGestureRecognizer.self) {
			if toolbarIsOpening {
				return false
			}
			return true
		}

		guard
			let pan = gestureRecognizer as? UIPanGestureRecognizer,
			let scroll = (collectionView.visibleCells.first as? DisplayCell)?.contentScroll
		else { return true}
		if pan == dismissPan {
			if tapCount != 0{
				return false
			}
			if toolbarIsOpening {
				return false
			}
			if fabs(scroll.contentOffset.y + scroll.contentInset.top) < 1 {
				let velocity = pan.velocity(in: nil)
				return  velocity.y>fabs(velocity.x)
			}

			return false
		}
		if pan == toolbarPan {
			if tapCount != 0{
				return false
			}
			if toolbarIsOpening {
				return true
			}
			if fabs(scroll.contentOffset.y + scroll.frame.height - scroll.contentInset.top - scroll.contentSize.height) < 1 {
				let velocity = pan.velocity(in: nil)
				return velocity.y<0 && fabs(velocity.y)>fabs(velocity.x)
			}
			return false
		}


		return true
	}
}


import Photos
//MARK:	savePhoto
extension MDKImageDisplayController{

	func savePhoto() -> () {
		var failType : SavePhotoFailType?
		var failTypeObjc : MDKSavePhotoFailType?

		switch PHPhotoLibrary.authorizationStatus() {
		case .restricted:
			//没有权限
			failType = .restricted
			failTypeObjc = .restricted
		case .denied:
			failType = .denied
			failTypeObjc = .denied
		default:
			break
		}
		if failType != nil {

			if let savePhotoResultObjc = savePhotoResultObjc{
				let result = MDKSavePhotoResult()
				result.success = false
				result.failType = failTypeObjc!
				savePhotoResultObjc(result)
			}else{
				savePhotoResult?(.fail(failType!))
			}
			return
		}
		
		let displayIndex = self.displayIndex - photoList.negativeCount
		let option = MDKImageCloseOption()
		if displayIndex>0 {
			option.lastIdentifier = photoList[displayIndex-1].identifier
		}else if displayIndex<0{
			option.lastIdentifier = photoList[displayIndex+1].identifier
		}
		option.index = displayIndex
		option.needQuality = .large
		option.displayCtr = self
		let handlePhotoClose:ImageClose = {[weak self] photo in
			guard let photo = photo , let _self = self else {return}
			_self.photoList[displayIndex].photoQuality = .original

			_self.photoList[displayIndex].photo = photo
			UIImageWriteToSavedPhotosAlbum(photo, _self, #selector(_self.image(_:didFinishSavingWithError:contextInfo:)), nil)
		}
		if let largeIdentiferClose = largeIdentiferClose{
			let identifier = largeIdentiferClose(option,handlePhotoClose)
			if identifier != nil {
				photoList[displayIndex].identifier = identifier
			}
		}else{
			largeClose?(option,handlePhotoClose)
		}
	}

	@objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {


		if let savePhotoResultObjc = savePhotoResultObjc{
			let result = MDKSavePhotoResult()
			if let error = error {
				result.success = false
				result.failType = .saveingFail
				result.error = error
			}
			savePhotoResultObjc(result)
		}else{
			savePhotoResult?(error == nil ? .success : .fail(.saveingFail(error!)))
		}
	}
}

//系统功能
extension MDKImageDisplayController{
	override open var supportedInterfaceOrientations: UIInterfaceOrientationMask{
		return .all
	}

	@available(iOS 9.0, *)
	override open var previewActionItems: [UIPreviewActionItem]{
		var actionArr:[UIPreviewActionItem] = []
		actionArr.append(UIPreviewAction(title: "保存图片", style: .default, handler: {[weak self] (action, previewCtr) in
			self?.savePhoto()
		}))

		if self.photoList[0].photo == nil {
			let option = MDKImageCloseOption()
			option.index = 0
			option.needQuality = .thumbnail
			largeClose?(option){ photo in
				self.photoList[0].photo = photo
			}
			let _ = largeIdentiferClose?(option){ photo in
				self.photoList[0].photo = photo
			}
		}
		self.photoList[0].checkHasQRCode { }
		if let qrCode = self.photoList[0].QRCode {
			if (qrCode.count) > 0 {
				actionArr.append(UIPreviewAction(title: "识别图中的二维码", style: .default, handler: { (action, previewCtr) in
					self.QRCodeHandler(qrCode,nil)
				}))
			}
		}

		return actionArr
	}
}


extension MDKImageDisplayController:DisplayCellDelegate{
	func displayCell(_ cell: DisplayCell, scrollPanHandle pan: UIPanGestureRecognizer) {
		let velocity = pan.velocity(in: nil)
		if let imgSize =  cell.imageView.image?.size , cell.contentScroll.contentOffset.y >= cell.contentScroll.contentSize.height - imgSize.width/cell.contentScroll.contentSize.width*imgSize.height , velocity.y < 0 && !toolbarIsFinishOpen{

			if toolbar.superview == nil{
				resetToolbar(touchPoint: nil, cell: cell)
			}
			toolbarPanFunc(pan: pan)
			cell.canScroll = false
			cell.isScrolling = false
		}
	}
}
