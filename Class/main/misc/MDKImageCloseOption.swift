//
//  MDKImageCloseOption.swift
//  MDKImageCollection
//
//  Created by mikun on 2018/8/8.
//  Copyright © 2018年 mdk. All rights reserved.
//



@objc public class MDKImageCloseOption :NSObject{
	@objc public var lastIdentifier:String?
	@objc public var index:Int = 0
	@objc public var needQuality:LoadingPhotoQuality = .thumbnail
	@objc public var displayCtr:UIViewController?
}
