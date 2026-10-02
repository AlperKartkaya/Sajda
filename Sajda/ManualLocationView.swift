// MARK: - GANTI SELURUH FILE: ManualLocationView.swift

import SwiftUI
import NavigationStack

struct ManualLocationView: View {
    @EnvironmentObject var vm: PrayerTimeViewModel
    @EnvironmentObject var navigationModel: NavigationModel
    
    let isModal: Bool
    var parentNavigationID: String = LocationAndCalcSettingsView.id
    
    @State private var hoveringResult: String?
    @State private var isHeaderHovering = false

    private var viewWidth: CGFloat {
        return vm.useCompactLayout ? 220 : 260
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: handleBackButton) {
                HStack {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    Text(LocalizedStringKey("Konum seç")).font(.body).fontWeight(.bold)
                    Spacer()
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(isHeaderHovering ? Color("HoverColor") : .clear).cornerRadius(5)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 5).padding(.top, 2)
            .onHover { hovering in isHeaderHovering = hovering }
            
            Divider().padding(.horizontal, 12).drawingGroup()
            
            TextField(LocalizedStringKey("İl ara..."), text: $vm.locationSearchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
            
            ScrollView {
                if vm.locationSearchResults.isEmpty {
                    Text("Sonuç bulunamadı.").foregroundColor(.secondary).padding()
                }
                VStack(spacing: 2) {
                    ForEach(vm.locationSearchResults, id: \.self) { province in
                        Button(action: {
                            vm.setManualProvince(province)
                            handleBackButton()
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
                        .onHover { isHovering in hoveringResult = isHovering ? province : nil }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 280)
        }
        .padding(.vertical, 8)
        .frame(width: viewWidth)
        .onDisappear {
            vm.locationSearchQuery = ""
        }
    }
    
    private func handleBackButton() {
        if isModal {
            navigationModel.hideView(ContentView.id, animation: vm.backwardAnimation())
        } else {
            navigationModel.hideView(parentNavigationID, animation: vm.backwardAnimation())
        }
    }
}
