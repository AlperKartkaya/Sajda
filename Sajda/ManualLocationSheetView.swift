// MARK: - GANTI SELURUH FILE: ManualLocationSheetView.swift (SOLUSI LAYOUT FINAL)

import SwiftUI

struct ManualLocationSheetView: View {
    @EnvironmentObject var vm: PrayerTimeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var hoveringResult: String?

    var body: some View {
        VStack(spacing: 16) {
            
            VStack {
                Text("Konum seç")
                    .font(.headline)
                Text("Türkiye illeri — internet bağlantısı gerekmez.")
                    .font(.subheadline)
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .padding(.top, 8)

            TextField("İl ara...", text: $vm.locationSearchQuery)
                .textFieldStyle(.roundedBorder)
            
            if vm.locationSearchResults.isEmpty {
                // --- KUNCI PERBAIKAN 2 ---
                // Bungkus dalam VStack dengan Spacer agar tetap di atas.
                VStack {
                    Text(vm.locationSearchQuery.isEmpty ? " " : "No results found.")
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                    Spacer()
                }
            } else {
                // --- KUNCI PERBAIKAN 3 ---
                // ScrollView dibiarkan sendiri tanpa Spacer,
                // sehingga ia akan mengisi sisa ruang secara otomatis.
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(vm.locationSearchResults, id: \.self) { province in
                            Button(action: {
                                vm.setManualProvince(province)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(province).fontWeight(.semibold)
                                        Text("Türkiye").font(.caption).foregroundColor(Color("SecondaryTextColor"))
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .background(hoveringResult == province ? Color("HoverColor") : Color.clear)
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                hoveringResult = isHovering ? province : nil
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding()
        .frame(width: 320, height: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .animation(.easeInOut, value: vm.locationSearchResults.count)
        .onDisappear {
            vm.locationSearchQuery = ""
        }
    }
}
