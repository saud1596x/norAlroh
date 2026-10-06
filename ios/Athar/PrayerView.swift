import SwiftUI

struct PrayerView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var notifications: PrayerNotifications
    @State private var choosingCity = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button { choosingCity = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.crop.circle").font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.data.city.name).font(.headline)
                            Text("\(store.data.city.region ?? "") · المملكة العربية السعودية").font(.caption)
                        }
                        Spacer(); Image(systemName: "chevron.down")
                    }.padding(18).foregroundStyle(Theme.gold)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(NoorPressStyle()).accessibilityLabel("تغيير مدينة مواقيت الصلاة")
                    .accessibilityIdentifier("prayer.city")
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let rows = PrayerCalculator.rows(data: store.data, date: context.date)
                    let next = PrayerCalculator.next(data: store.data, now: context.date)
                    VStack(spacing: 18) {
                        if let next {
                            VStack(spacing: 12) {
                                Text("الصلاة القادمة").font(.subheadline)
                                Text(next.name).font(.largeTitle.bold())
                                Text(PrayerCalculator.time(next.date, city: store.data.city))
                                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                                Text(timerInterval: context.date...next.date, countsDown: true)
                                    .font(.title3.monospacedDigit()).accessibilityLabel("الوقت المتبقي للصلاة")
                            }.frame(maxWidth: .infinity).padding(26)
                                .foregroundStyle(Theme.buttonInk)
                                .background(Theme.gold, in: RoundedRectangle(cornerRadius: 28))
                                .overlay(alignment: .topLeading) { NoorAmbientOrnament(ink: Theme.buttonInk).frame(width: 110, height: 110).padding(10) }
                                .noorEntrance()
                        }
                        Card {
                            Label("مواقيت اليوم", systemImage: "sun.horizon").font(.title3.bold())
                            ForEach(rows) { row in
                                HStack(spacing: 14) {
                                    Image(systemName: symbol(row.id)).foregroundStyle(Theme.gold).frame(width: 28)
                                    Text(row.name).font(.headline)
                                    if let next, next.id == row.id, PrayerCalculator.isSameSaudiDay(next.date, context.date) {
                                        Text("القادمة").font(.caption).foregroundStyle(Theme.gold)
                                    }
                                    Spacer()
                                    Text(PrayerCalculator.time(row.date, city: store.data.city)).font(.title3.monospacedDigit())
                                }.padding(12).frame(minHeight: 48)
                                    .background(next.map { $0.id == row.id && PrayerCalculator.isSameSaudiDay($0.date, context.date) } == true ? Theme.gold.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                            }
                            if rows.isEmpty { Text("تعذر حساب المواقيت. اختر مدينة أخرى.").foregroundStyle(.secondary) }
                        }
                    }
                }
                Card {
                    Label("تنبيهات الصلاة", systemImage: "bell.badge").font(.title3.bold())
                    NavigationLink { PrayerNotificationSettings() } label: {
                        HStack { Text("اختر الصلوات ووقت التنبيه"); Spacer(); Image(systemName: "chevron.left") }.frame(minHeight: 44)
                    }.buttonStyle(NoorPressStyle())
                    if !notifications.enabled {
                        Button(notifications.requestingPermission ? "طلب إذن الإشعارات…" : "تفعيل الإشعارات") { Task { await notifications.enable(store: store) } }.frame(minHeight: 44).disabled(notifications.requestingPermission)
                    }
                    if let message = notifications.message { Text(message).font(.caption).foregroundStyle(Theme.gold) }
                }
                Card {
                    Text("طريقة الحساب").font(.headline)
                    Picker("الحساب", selection: Binding(get: { store.data.method }, set: { v in store.update { $0.method = v } })) {
                        Text("أم القرى · رمضان تلقائيًا").tag("UmmAlQura")
                        Text("أم القرى · عشاء ١٢٠ دقيقة").tag("UmmAlQuraRamadan")
                    }.pickerStyle(.menu)
                    Text("المواقيت محسوبة لمركز المدينة بتوقيت المملكة. أم القرى: العشاء بعد المغرب بـ٩٠ دقيقة، و١٢٠ دقيقة في رمضان بحسب تقويم أم القرى على الجهاز. قارنها بالتقويم الرسمي والمسجد المحلي.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("مواقيت الصلاة")
            .sheet(isPresented: $choosingCity) { NavigationStack { SaudiCityPicker() } }
            .task(id: "\(store.data.city.id)-\(store.data.method)-\(store.data.hanafi)") { await notifications.refresh(store: store) }
    }
    private func symbol(_ id: String) -> String {
        switch id { case "fajr": "sunrise"; case "sunrise": "sunrise.fill"; case "dhuhr": "sun.max";
        case "asr": "sun.haze"; case "maghrib": "sunset"; default: "moon.stars" }
    }
}

struct SaudiCityPicker: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var region = "الكل"
    private var regions: [String] { ["الكل"] + Set(City.all.compactMap(\.region)).sorted() }
    private var results: [City] {
        let query = ArabicSearch.normalize(search)
        return City.all.filter { (region == "الكل" || $0.region == region)
            && (query.isEmpty || ArabicSearch.normalize($0.name).contains(query) || ArabicSearch.normalize($0.region ?? "").contains(query)) }
    }
    var body: some View {
        List {
            Section {
                Picker("المنطقة", selection: $region) { ForEach(regions, id: \.self) { Text($0).tag($0) } }
            }
            Section("مدن المملكة") {
                ForEach(results) { city in
                    Button {
                        if store.update({ $0.city = city; if !["UmmAlQura", "UmmAlQuraRamadan"].contains($0.method) { $0.method = "UmmAlQura" } }) { dismiss() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(city.name).font(.headline).foregroundStyle(.primary)
                                Text(city.region ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.data.city.id == city.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
                        }.frame(minHeight: 48)
                    }.accessibilityIdentifier("city.\(city.id)")
                }
                if results.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }.searchable(text: $search, prompt: "ابحث عن مدينة سعودية")
            .navigationTitle("اختيار المدينة")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("تم") { dismiss() } } }
            .tint(Theme.gold)
    }
}
