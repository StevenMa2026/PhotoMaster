//
//  PhotoClassifiable.swift
//  PhotoMaster
//
//  Created by Steven Ma on 2026/3/20.
//

import Photos
import UIKit

protocol PhotoClassifiable {
    var albumName: String { get }
    func matches(image: CGImage, asset: PHAsset) -> Bool
    func albumName(for asset: PHAsset) -> String
    // If true, once this classifier matches we will stop evaluating later classifiers.
    var exclusive: Bool { get }
    // Which media types this classifier should run on.
    var supportedMediaTypes: Set<PHAssetMediaType> { get }
    // Which album types this classifier should search in (empty means use default scan range)
    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] { get }
    // Which album names this classifier should search in (empty means no album name restriction)
    var supportedAlbumNames: Set<String> { get }
    // Whether this classifier needs high-resolution images (e.g. OCR). Defaults to false.
    var requiresHighResolution: Bool { get }
}

extension PhotoClassifiable {
    func albumName(for asset: PHAsset) -> String {
        albumName
    }

    var exclusive: Bool { false }

    var supportedMediaTypes: Set<PHAssetMediaType> { [.image] }

    var supportedAlbumTypes: [(type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype)] {
        // Default to empty, which means use default scan range
        []
    }

    var supportedAlbumNames: Set<String> {
        // Default to empty, which means no album name restriction
        []
    }

    var requiresHighResolution: Bool { false }
}