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
                        detail: "點按英文字母後，從鍵盤上方的候選列直接選取中文字。已學習的智能候選會以藍色顯示，普通 Space 提交智能首選。"
                    )
                    instruction(
                        number: 4,
                        title: "輸出英文字",
                        detail: "Shift-Space：輸出英文字，不輸出對應倉頡字。"
                    )

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
            Text("HybridIME 是支援智能候選、英文直接輸入及 Emoji 的 iOS 倉頡鍵盤。")
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
