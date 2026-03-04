//
//  WalmartItems.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 2/27/26.
//

import Foundation

struct WalmartItem: Identifiable, Decodable {
    let id: Int
    let name: String
    let ingredient: Bool?
    let classifiers: String?
    let retail_price: Double?
    let thumbnailImage: String?
    let mediumImage: String?
    let largeImage: String?
    let color: String?
}

