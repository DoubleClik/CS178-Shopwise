//
//  AuthManagerGate.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 2/2/26.
//

import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if auth.isSignedIn {
                // ✅ Your main app view (what you showed in screenshot)
                ContentView()
            } else {
                AuthView()
            }
        }
    }
}
