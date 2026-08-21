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
                    instruction(
                        number: 5,
                        title: "私隱與離線學習",
                        detail: "鍵盤以離線詞典運作，不連線且不要求「允許完整取用」。為改善候選排序而記錄的倉頡碼、已選候選及有限前文，只儲存在此裝置的鍵盤 extension 本機容器，不會傳送給開發者或第三方。刪除本 App（連同鍵盤 extension）會移除這些本機學習資料。"
                    )
                    instruction(
                        number: 6,
                        title: "系統限制",
                        detail: "密碼等安全文字欄位、電話／姓名電話鍵盤，以及停用第三方鍵盤的 App，會由 iOS 顯示系統鍵盤；這些情況無法使用 HybridIME。"
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
            Text("HybridIME 是支援智能候選及英文直接輸入的 iOS 倉頡鍵盤。")
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
