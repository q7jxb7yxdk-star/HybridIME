//
//  ContentView.swift
//  HybridIME
//
//  Created by Sunny Yu on 12/6/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("HybridIME", systemImage: "keyboard")
                .font(.largeTitle.bold())

            Text("中英文混合倉頡五代輸入法")
                .font(.title3)

            Divider()

            instruction(
                "1",
                "將編譯後的 HybridIME.app 放入 ~/Library/Input Methods。"
            )
            instruction(
                "2",
                "登出再登入，然後在「系統設定 > 鍵盤 > 文字輸入」加入 HybridIME。"
            )
            instruction(
                "3",
                "輸入倉頡碼；Space 輸出英文，Return 輸出首個中文候選字，數字鍵選擇其他候選字。"
            )

            Text("內建 Rime 倉頡五代完整單字碼表，包含 Unicode 擴展區漢字。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("碼表來源：github.com/rime/rime-cangjie，依 LGPL-3.0 授權。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 560, alignment: .leading)
        .padding(28)
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
