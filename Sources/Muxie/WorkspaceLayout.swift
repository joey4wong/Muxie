// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 Yunyi Tang. See LICENSE.

import Foundation

enum WorkspaceLayout {
    static let rowHeight: CGFloat = 60
    static let rowSpacing: CGFloat = 8
    static let filterHeight: CGFloat = 32
    static let listInsets: CGFloat = 36
    static let filterGap: CGFloat = 12
    static let paginationHeight: CGFloat = 32
    static let exportHeight: CGFloat = 132
    static let activityHeight: CGFloat = 72
    static let chromeAllowance: CGFloat = 60

    static func trackSectionHeight(rows: Int, pagination: Bool = false) -> CGFloat {
        let count = max(1, rows)
        return listInsets + filterHeight + filterGap
            + CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
            + (pagination ? paginationHeight : 0)
    }
    static func minimumContentHeight(rows: Int, pagination: Bool = false) -> CGFloat {
        trackSectionHeight(rows: rows, pagination: pagination) + exportHeight + activityHeight
    }
    static func pageCapacity(screenHeight: CGFloat, pagination: Bool = false) -> Int {
        let fixed = minimumContentHeight(rows: 1, pagination: pagination) - rowHeight + chromeAllowance
        return max(1, Int(floor((screenHeight - fixed + rowSpacing) / (rowHeight + rowSpacing))))
    }
}
