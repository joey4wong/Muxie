// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import SwiftUI

struct SettingsView: View {
    @AppStorage(CompressEncoder.defaultsKey) private var encoderRaw = CompressEncoder.hardware.rawValue
    var body: some View {
        Form {
            Picker("Compress encoder", selection: $encoderRaw) {
                ForEach(CompressEncoder.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.radioGroup)
            Text((CompressEncoder(rawValue: encoderRaw) ?? .hardware).detail)
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
