import Foundation
import GRDB
import HearthstockCore
import os

extension DatabaseMigrator {
    /// Registers every migration in order. Append new ones at the end; never edit one that has shipped.
    mutating func registerHearthstockMigrations() {
        registerMigration("v1_initial", migrate: createInitialSchema)
        registerMigration("v2_site_notice_window", migrate: addSiteNoticeWindow)
        registerMigration("v3_normalize_barcodes", migrate: normalizeBarcodes)
        registerMigration("v4_lot_no_printed_date", migrate: addLotNoPrintedDate)
        registerMigration("v5_lookup_cache", migrate: createLookupCache)
    }
}

private let migrationLog = Logger(subsystem: "dev.0xhampton.hearthstock", category: "migrations")

/// Slice 4: product barcodes in the one form `Barcode` gives (UPC-A, UPC-E and EAN-13 become one 13-digit GTIN), so
/// a scan finds a product saved from a typed code.
///
/// A barcode that isn't valid, or whose normalized form another product already has, is left as it is and logged:
/// the unique index would refuse the duplicate, and merging products is a person's call. `find(barcode:)` still
/// matches those exactly. The rules are the GS1 standard, so calling Core's `Barcode` from a shipped migration
/// won't change what it does.
private func normalizeBarcodes(_ db: Database) throws {
    let rows = try Row.fetchAll(db, sql: "SELECT id, barcode FROM product WHERE barcode IS NOT NULL ORDER BY id")
    var taken = Set(rows.map { $0["barcode"] as String })
    for row in rows {
        let id: String = row["id"], raw: String = row["barcode"]
        guard let normalized = try? Barcode(raw).rawValue else {
            migrationLog.notice("v3_normalize_barcodes: kept invalid barcode \(raw, privacy: .public) on product \(id, privacy: .public)")
            continue
        }
        guard normalized != raw else { continue }
        guard !taken.contains(normalized) else {
            migrationLog.notice("v3_normalize_barcodes: kept \(raw, privacy: .public) on product \(id, privacy: .public); \(normalized, privacy: .public) is another product's")
            continue
        }
        try db.execute(sql: "UPDATE product SET barcode = ? WHERE id = ?", arguments: [normalized, id])
        taken.remove(raw)
        taken.insert(normalized)
    }
}

/// Slice 4 Decision 1: a lot marked as having no printed date, aged from an estimate. Never set together with a
/// printed date. Existing lots start with it off (Decision 4).
private func addLotNoPrintedDate(_ db: Database) throws {
    try db.execute(sql: """
        ALTER TABLE lot ADD COLUMN noPrintedDate INTEGER NOT NULL DEFAULT 0
            CHECK (noPrintedDate IN (0, 1) AND (noPrintedDate = 0 OR printedDate IS NULL))
        """)
}

/// Slice 4 Decision 7: every Open Food Facts answer (found or not found), one row per normalized barcode, so each
/// barcode leaves the phone at most once. Nothing references it; products never point at it.
private func createLookupCache(_ db: Database) throws {
    try db.execute(sql: """
        CREATE TABLE lookup_cache (
            barcode TEXT PRIMARY KEY NOT NULL CHECK (barcode <> ''),
            outcome TEXT NOT NULL CHECK (outcome IN ('found', 'notFound')),
            product TEXT CHECK ((outcome = 'found') = (product IS NOT NULL)),
            fetchedAt TEXT NOT NULL
        )
        """)
}

/// Slice 3: each site's Use soon notice window, in whole days.
private func addSiteNoticeWindow(_ db: Database) throws {
    try db.execute(sql: """
        ALTER TABLE site ADD COLUMN noticeWindowDays INTEGER NOT NULL DEFAULT 30 CHECK (noticeWindowDays > 0)
        """)
}

/// Everything Slice 1 models, saved to SQLite.
///
/// The CHECK lists below repeat the raw values of the Core enums on purpose: a shipped migration
/// must not change when an enum later gains a case. `SchemaTests` fails if a Core case is missing
/// from a list, which is the cue to add a new migration.
private func createInitialSchema(_ db: Database) throws {
    let timestamps = """
        createdAt TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        updatedAt TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        """
    let climateClasses = """
        'coolDry', 'rootCellar', 'climateControlled', 'insulatedUnconditioned', 'hot', 'vehicle', \
        'refrigerated', 'frozen'
        """

    // Calendar dates are ISO `YYYY-MM-DD` text. `date(x) IS x` rejects malformed text and impossible
    // days alike (date() returns NULL or a normalised date, neither equal to the input).
    func isoDate(_ column: String) -> String { "\(column) IS NULL OR date(\(column)) IS \(column)" }

    try db.execute(sql: """
        CREATE TABLE site (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL CHECK (name <> ''),
            \(timestamps)
        );

        CREATE TABLE person (
            id TEXT PRIMARY KEY NOT NULL,
            siteId TEXT NOT NULL REFERENCES site(id) ON DELETE CASCADE,
            name TEXT NOT NULL CHECK (name <> ''),
            kcalPerDay REAL NOT NULL CHECK (kcalPerDay >= 0),
            waterGalPerDay REAL NOT NULL CHECK (waterGalPerDay >= 0),
            \(timestamps)
        );

        -- location and kit reference each other, so kitId is checked at commit.
        CREATE TABLE location (
            id TEXT PRIMARY KEY NOT NULL,
            siteId TEXT NOT NULL REFERENCES site(id) ON DELETE RESTRICT,
            parentId TEXT REFERENCES location(id) ON DELETE RESTRICT CHECK (parentId IS NULL OR parentId <> id),
            name TEXT NOT NULL CHECK (name <> ''),
            climateClass TEXT CHECK (climateClass IS NULL OR climateClass IN (\(climateClasses))),
            climateMultiplierOverride REAL CHECK (climateMultiplierOverride IS NULL OR climateMultiplierOverride > 0),
            humidity TEXT CHECK (humidity IS NULL OR humidity IN ('dry', 'humid')),
            kitId TEXT REFERENCES kit(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
            \(timestamps)
        );

        CREATE TABLE kit (
            id TEXT PRIMARY KEY NOT NULL,
            homeSiteId TEXT NOT NULL REFERENCES site(id) ON DELETE RESTRICT,
            locationId TEXT NOT NULL UNIQUE REFERENCES location(id) ON DELETE RESTRICT,
            templateId TEXT,
            countsTowardSiteRunway INTEGER NOT NULL DEFAULT 0 CHECK (countsTowardSiteRunway IN (0, 1)),
            lastInspected TEXT CHECK (\(isoDate("lastInspected"))),
            \(timestamps)
        );

        CREATE TABLE product (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL CHECK (name <> ''),
            barcode TEXT CHECK (barcode IS NULL OR barcode <> ''),
            category TEXT NOT NULL CHECK (category IN ('food', 'water', 'power', 'medical', 'tools', 'hygiene', 'other')),
            role TEXT NOT NULL CHECK (role IN ('supply', 'capability', 'consumable')),
            unitKind TEXT NOT NULL CHECK (unitKind IN ('mass', 'volume', 'energy', 'count')),
            kcalPerBaseUnit REAL CHECK (kcalPerBaseUnit IS NULL OR kcalPerBaseUnit >= 0),
            potableWaterGalPerBaseUnit REAL
                CHECK (potableWaterGalPerBaseUnit IS NULL OR potableWaterGalPerBaseUnit >= 0),
            shelfLifeProfileKey TEXT NOT NULL CHECK (shelfLifeProfileKey <> ''),
            \(timestamps)
        );

        CREATE TABLE lot (
            id TEXT PRIMARY KEY NOT NULL,
            siteId TEXT NOT NULL REFERENCES site(id) ON DELETE RESTRICT,
            productId TEXT NOT NULL REFERENCES product(id) ON DELETE RESTRICT,
            locationId TEXT NOT NULL REFERENCES location(id) ON DELETE RESTRICT,
            quantity REAL NOT NULL CHECK (quantity >= 0),
            acquiredDate TEXT NOT NULL CHECK (\(isoDate("acquiredDate"))),
            printedDate TEXT CHECK (\(isoDate("printedDate"))),
            packaging TEXT NOT NULL DEFAULT 'none' CHECK (packaging IN ('none', 'mylarO2', 'bucket', 'stabilized')),
            climateOverride TEXT CHECK (climateOverride IS NULL OR climateOverride IN (\(climateClasses))),
            opened INTEGER NOT NULL DEFAULT 0 CHECK (opened IN (0, 1)),
            archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
            notes TEXT,
            \(timestamps)
        );

        -- An override belongs to exactly one product or one lot, and goes with it.
        CREATE TABLE shelf_life_override (
            id TEXT PRIMARY KEY NOT NULL,
            productId TEXT REFERENCES product(id) ON DELETE CASCADE,
            lotId TEXT REFERENCES lot(id) ON DELETE CASCADE,
            dateType TEXT CHECK (dateType IS NULL OR dateType IN ('bestBy', 'useBy', 'none')),
            extensionMonths INTEGER CHECK (extensionMonths IS NULL OR extensionMonths >= 0),
            packagedLifeMonths INTEGER CHECK (packagedLifeMonths IS NULL OR packagedLifeMonths >= 0),
            rotationMonths INTEGER CHECK (rotationMonths IS NULL OR rotationMonths >= 0),
            \(timestamps),
            CHECK ((productId IS NOT NULL) + (lotId IS NOT NULL) = 1)
        );

        CREATE INDEX lot_on_site_archived ON lot(siteId, archived);
        CREATE INDEX lot_on_product ON lot(productId);
        CREATE INDEX lot_on_location ON lot(locationId);
        CREATE INDEX location_on_site ON location(siteId);
        CREATE UNIQUE INDEX product_on_barcode ON product(barcode) WHERE barcode IS NOT NULL;
        CREATE UNIQUE INDEX shelf_life_override_on_product ON shelf_life_override(productId) WHERE productId IS NOT NULL;
        CREATE UNIQUE INDEX shelf_life_override_on_lot ON shelf_life_override(lotId) WHERE lotId IS NOT NULL;
        """)

    // A site's runway reads lots through their location, so a lot filed under the wrong site would
    // silently corrupt it. These triggers refuse the write however it arrives. A missing location
    // is left to the foreign key.
    try db.execute(sql: """
        CREATE TRIGGER lot_site_matches_location_insert BEFORE INSERT ON lot
        WHEN EXISTS (SELECT 1 FROM location WHERE id = NEW.locationId AND siteId <> NEW.siteId)
        BEGIN
            SELECT RAISE(ABORT, 'lot.siteId must equal its location''s siteId');
        END;

        CREATE TRIGGER lot_site_matches_location_update BEFORE UPDATE OF siteId, locationId ON lot
        WHEN EXISTS (SELECT 1 FROM location WHERE id = NEW.locationId AND siteId <> NEW.siteId)
        BEGIN
            SELECT RAISE(ABORT, 'lot.siteId must equal its location''s siteId');
        END;

        CREATE TRIGGER location_site_change_guard BEFORE UPDATE OF siteId ON location
        WHEN NEW.siteId <> OLD.siteId AND (
            EXISTS (SELECT 1 FROM lot WHERE locationId = OLD.id)
            OR EXISTS (SELECT 1 FROM location WHERE parentId = OLD.id)
            OR EXISTS (SELECT 1 FROM kit WHERE locationId = OLD.id)
        )
        BEGIN
            SELECT RAISE(ABORT, 'a location holding lots, children or a kit cannot change site');
        END;

        CREATE TRIGGER location_parent_same_site_insert BEFORE INSERT ON location
        WHEN NEW.parentId IS NOT NULL
            AND EXISTS (SELECT 1 FROM location WHERE id = NEW.parentId AND siteId <> NEW.siteId)
        BEGIN
            SELECT RAISE(ABORT, 'a location''s parent must be in the same site');
        END;

        CREATE TRIGGER location_parent_same_site_update BEFORE UPDATE OF siteId, parentId ON location
        WHEN NEW.parentId IS NOT NULL
            AND EXISTS (SELECT 1 FROM location WHERE id = NEW.parentId AND siteId <> NEW.siteId)
        BEGIN
            SELECT RAISE(ABORT, 'a location''s parent must be in the same site');
        END;

        CREATE TRIGGER kit_home_site_matches_location_insert BEFORE INSERT ON kit
        WHEN EXISTS (SELECT 1 FROM location WHERE id = NEW.locationId AND siteId <> NEW.homeSiteId)
        BEGIN
            SELECT RAISE(ABORT, 'kit.homeSiteId must equal its location''s siteId');
        END;

        CREATE TRIGGER kit_home_site_matches_location_update BEFORE UPDATE OF homeSiteId, locationId ON kit
        WHEN EXISTS (SELECT 1 FROM location WHERE id = NEW.locationId AND siteId <> NEW.homeSiteId)
        BEGIN
            SELECT RAISE(ABORT, 'kit.homeSiteId must equal its location''s siteId');
        END;
        """)
}
