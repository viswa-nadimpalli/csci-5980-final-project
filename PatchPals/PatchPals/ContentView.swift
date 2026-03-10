//
//  ContentView.swift
//  PatchPals
//
//  Created by Leo Curtis on 3/8/26.
//

import SwiftUI

struct ContentView: View {
    @State private var packs: [Pack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let userID = "4146544a-0464-42bd-b14e-6185b1e75f9a"

    var body: some View {
        NavigationStack {
            Text("Sticker Pack App").font(.largeTitle)

            if let firstPack = packs.first {
                VStack {
                    Text("First Pack:").font(.headline)
                    Text(firstPack.name).font(.title2)

                    if let description = firstPack.description {
                        Text(description)
                            .foregroundColor(.secondary)
                    }
                }
            } else if !isLoading {
                Text("is loading")
                    .foregroundColor(.gray)
            }
            
            // Button("Delete Sticker") {
            //     Task{
            //         do{
            //             try await APIClient.shared.deleteSticker(
            //                 stickerID: stickerID,
            //                 userID: userID
            //             )
            //             print("Sticker has been deleted")
            //         } catch {
            //             print("Delete unsucessful: ", error)
                        
            //         }
            //     }
            // }
        }
        .padding()
        .task {
                await loadPacks()
        }
    }

    private func loadPacks() async {
        isLoading = true
        errorMessage = nil

        do {
            packs = try await APIClient.shared.fetchPacks(requesterID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    ContentView()
}
