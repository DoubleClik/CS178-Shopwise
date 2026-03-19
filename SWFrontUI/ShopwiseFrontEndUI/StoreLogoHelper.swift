//  StoreLogoHelper.swift
//  ShopwiseFrontEndUI
//
//  Shared helper — maps store names to Assets.xcassets image names.
//  Used by SearchView, MapView, and anywhere else store logos are needed.

import UIKit

func storeLogoAsset(for storeName: String) -> String? {
    switch storeName {
    case "Walmart":
        return "logo_walmart"
    case "Ralphs", "Ralphs Delivery Now":
        return "logo_ralphs"
    case "Food4Less", "Food 4 Less":
        return "logo_food4less"
    case "Stater Bros.", "Stater Bros. Now":
        return "logo_stater"
    case "Sprouts", "Sprouts Farmers Market", "Sprouts Express":
        return "logo_sprouts"
    case "ALDI":
        return "logo_aldi"
    case "Smart & Final", "Smart & Final Extra!":
        return "logo_smartfinal"
    case "99 Ranch", "99 Ranch Market":
        return "logo_99ranch"
    default:
        return nil
    }
}
