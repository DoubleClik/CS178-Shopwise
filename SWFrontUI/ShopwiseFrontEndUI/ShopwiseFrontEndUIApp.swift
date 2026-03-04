//
//  ShopwiseFrontEndUIApp.swift
//  ShopwiseFrontEndUI
//
//  Created by James Chang on 1/13/26.
//  Edited by Nicholas Castellanos

//import SwiftUI
//import SwiftData
//
//@main
//struct Shopwise: App {
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//        }
//    }
//}


import SwiftUI
import SwiftData

@main
struct ShopwiseFrontEndUIApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(auth)
        }
    }
}
