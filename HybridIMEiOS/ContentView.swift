import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    instruction(
                        number: 1,
                        title: "加入鍵盤",
                        detail: "前往「設定」→「一般」→「鍵盤」→「鍵盤」→「新增鍵盤」，選擇 HybridIMEKeyboard。"
                    )
                    instruction(
                        number: 2,
                        title: "切換至 HybridIME",
                        detail: "在任何支援第三方鍵盤的文字欄位，長按地球鍵並選擇 HybridIMEKeyboard。"
                    )
                    instruction(
                        number: 3,
                        title: "輸入倉頡碼",
                        detail: "點按英文字母後，從鍵盤上方的候選列直接選取中文字。Space 提交英文，Return 優先提交第一個中文候選。"
                    )

                    Label(
                        "此 POC 完全離線，不需要開啟「允許完整取用」。",
                        systemImage: "lock.shield"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                    Text("概念驗證版本")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(24)
            }
            .navigationTitle("HybridIME")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("中英混合倉頡鍵盤")
                .font(.title2.bold())
            Text("這個版本用來驗證 HybridIME 的基本倉頡輸入能否在 iOS Custom Keyboard Extension 運作。")
                .foregroundStyle(.secondary)
        }
    }

    private func instruction(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 32, height: 32)
                .foregroundStyle(.white)
                .background(.tint, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
