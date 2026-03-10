//
//  AuthManagerGate.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 2/2/26.
//

import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject var auth: AuthManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if auth.isSignedIn {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    NavigationStack {
                        OnboardingSurveyView()
                    }
                }
            } else {
                AuthView()
            }
        }
        .task {
            await auth.restoreSession()
        }
    }
}
