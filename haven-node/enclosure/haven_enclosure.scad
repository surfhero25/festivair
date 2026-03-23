// =============================================================================
// FestivAir Haven Mesh Node — Enclosure
// =============================================================================
//
// Housing for: Raspberry Pi 5 + LiFePO4 battery + HaLow WiFi module
// Deployment:  Outdoor music festival mesh network nodes
// Printer:     Bambu Lab P2S (256 x 256 x 256 mm build volume)
// Material:    PETG
//
// Usage:
//   Set `part` to "body", "lid", or "assembly" (preview only).
//   Export body and lid as separate STL files for printing.
//
// =============================================================================

// ===================== RENDER SELECTOR =======================================
// "body"     — main enclosure body (print this)
// "lid"      — top lid with seal lip and AP mount posts (print this)
// "assembly" — exploded preview of both parts together
part = "assembly";   // <-- change this for export

// ===================== COMPONENT DIMENSIONS =================================
pi_w    = 85;       // Raspberry Pi 5 — width (X)
pi_d    = 56;       // Raspberry Pi 5 — depth (Y)
pi_h    = 20;       // Raspberry Pi 5 — height (Z) including heatsink

bat_w   = 150;      // LiFePO4 battery — width (X)
bat_d   = 65;       // LiFePO4 battery — depth (Y)
bat_h   = 95;       // LiFePO4 battery — height (Z)

halow_w = 60;       // HaLow WiFi module — width (X)
halow_d = 40;       // HaLow WiFi module — depth (Y)
halow_h = 10;       // HaLow WiFi module — height (Z)

// ===================== ENCLOSURE PARAMETERS ==================================
wall          = 3;          // Wall thickness (PETG — good layer adhesion)
clearance     = 2;          // Clearance around components
vent_slot_w   = 2;          // Vent slot width
vent_slot_gap = 3;          // Gap between vent slots
seal_lip      = 1.5;        // Lid overlap lip depth
corner_r      = 3;          // Corner rounding radius

// ===================== DERIVED INTERIOR DIMENSIONS ===========================
int_w = bat_w + clearance * 2;
int_d = max(pi_d, bat_d) + halow_d + clearance * 3;
int_h = bat_h + clearance * 2;

// ===================== DERIVED EXTERIOR DIMENSIONS ===========================
ext_w = int_w + wall * 2;
ext_d = int_d + wall * 2;
ext_h = int_h + wall * 2;

// ===================== CURVE QUALITY =========================================
$fn = 60;

// ===================== FASTENER PARAMETERS ===================================
m3_hole       = 3.2;        // M3 clearance hole
m3_boss_od    = 8;           // M3 screw boss outer diameter
m3_boss_h     = 10;          // M3 screw boss height (lid attachment)
m4_hole       = 4.2;         // M4 clearance hole
m4_boss_od    = 10;          // M4 boss for AP mount
m4_boss_h     = 8;           // M4 AP mount post height

// Lid screw boss inset from exterior corner
lid_boss_inset = 10;

// ===================== INCLUDE COMPONENT MODULES =============================
include <components/pi_mount.scad>
include <components/battery_bay.scad>
include <components/vents.scad>
include <components/tripod_mount.scad>

// =============================================================================
//  UTILITY MODULES
// =============================================================================

// Rounded rectangle (centered, 2D profile for extrusion)
module rounded_rect_2d(w, d, r) {
    offset(r = r)
        square([w - 2*r, d - 2*r], center = true);
}

// Rounded box (centered XY, Z starts at 0)
module rounded_box(w, d, h, r) {
    linear_extrude(height = h)
        rounded_rect_2d(w, d, r);
}

// =============================================================================
//  MAIN BODY
// =============================================================================
module body() {
    difference() {
        union() {
            // --- Outer shell (open-top box) ---
            difference() {
                rounded_box(ext_w, ext_d, ext_h, corner_r);
                // Hollow interior
                translate([0, 0, wall])
                    rounded_box(int_w, int_d, ext_h, corner_r - wall/2);
            }

            // --- Internal: Pi 5 mounting standoffs ---
            // Pi sits in the front-left area, beside the battery
            pi_x = -int_w/2 + clearance + pi_w/2;
            pi_y = -int_d/2 + clearance + pi_d/2;
            translate([pi_x, pi_y, wall])
                pi5_mount(standoff_height = 5);

            // --- Internal: Battery bay retaining walls ---
            bat_x = int_w/2 - clearance - bat_w/2;
            bat_y = -int_d/2 + clearance + bat_d/2;
            translate([bat_x, bat_y, wall])
                battery_bay(bat_w, bat_d, bat_h, clearance);

            // --- Internal: HaLow module shelf ---
            // Shelf sits above the Pi area, at the back (high Y)
            halow_shelf_x = pi_x;
            halow_shelf_y = int_d/2 - clearance - halow_d/2;
            halow_shelf_z = wall + pi_h + 10;  // Above Pi + standoff clearance
            translate([halow_shelf_x, halow_shelf_y, halow_shelf_z])
                halow_shelf();

            // --- Lid screw bosses (4 corners, inside body walls) ---
            lid_boss_positions()
                lid_screw_boss_body();

            // --- Bottom: 1/4"-20 tripod mount boss ---
            // Centered on bottom exterior face
            // Boss grows inward (upward from floor)
            translate([0, 0, wall])
                tripod_boss();

            // --- Vent louver panels (left + right side walls) ---
            // Left wall (-X face)
            vent_h = int_h * 0.5;
            vent_w_actual = int_d * 0.5;
            translate([-ext_w/2, -vent_w_actual/2, wall + (int_h - vent_h)/2])
                rotate([0, 0, 0])
                    vent_assembly(w = vent_w_actual, h = vent_h,
                                  wall_t = wall, count = 8, angle = 45);
            // Right wall (+X face)
            translate([ext_w/2 - wall, -vent_w_actual/2, wall + (int_h - vent_h)/2])
                vent_assembly(w = vent_w_actual, h = vent_h,
                              wall_t = wall, count = 8, angle = 45);
        }

        // --- Subtract: Vent cutouts through left wall ---
        vent_h = int_h * 0.5;
        vent_w_actual = int_d * 0.5;
        translate([-ext_w/2 - 0.1, -vent_w_actual/2, wall + (int_h - vent_h)/2])
            louver_vent_cutout(w = vent_w_actual, h = vent_h, wall_t = wall + 0.2);
        // --- Subtract: Vent cutouts through right wall ---
        translate([ext_w/2 - wall - 0.1, -vent_w_actual/2, wall + (int_h - vent_h)/2])
            louver_vent_cutout(w = vent_w_actual, h = vent_h, wall_t = wall + 0.2);

        // --- Subtract: Bottom cable pass-throughs (2x oval, 15x8mm) ---
        cable_pass_y = -ext_d/2 + wall/2;
        for (cx = [-30, 30]) {
            translate([cx, cable_pass_y, wall/2])
                rotate([90, 0, 0])
                    oval_cutout(15, 8, wall + 2);
        }

        // --- Subtract: 1/4"-20 tripod hole through bottom floor ---
        translate([0, 0, -0.1])
            cylinder(d = insert_od, h = wall + 0.2);

        // --- Subtract: Pole clamp M6 bolt holes through back wall ---
        pole_bolt_spacing = 60;
        for (sx = [-1, 1]) {
            translate([sx * pole_bolt_spacing/2, ext_d/2 - wall/2, ext_h * 0.5])
                rotate([90, 0, 0])
                    cylinder(d = m6_hole, h = wall + 2, center = true);
        }
    }

    // --- External: 35mm pole clamp adapter on back face ---
    translate([0, ext_d/2 + pole_dia/2 + clamp_thickness * 0.3, ext_h * 0.35])
        rotate([0, 0, 180])
            pole_clamp();
}

// =============================================================================
//  LID
// =============================================================================
module lid() {
    lid_h = wall + seal_lip;

    difference() {
        union() {
            // --- Outer lid plate ---
            rounded_box(ext_w, ext_d, wall, corner_r);

            // --- Seal lip (drops into body opening) ---
            translate([0, 0, -seal_lip])
                difference() {
                    rounded_box(int_w - 0.4, int_d - 0.4, seal_lip, corner_r - wall/2);
                    // Hollow the lip so it's just a perimeter ring
                    translate([0, 0, -0.1])
                        rounded_box(int_w - 0.4 - wall, int_d - 0.4 - wall,
                                    seal_lip + 0.2, corner_r - wall);
                }

            // --- Top: Ubiquiti U6+ AP mount posts (100x100mm VESA-like) ---
            ap_pattern = 100;
            for (x = [-ap_pattern/2, ap_pattern/2])
                for (y = [-ap_pattern/2, ap_pattern/2])
                    translate([x, y, wall])
                        m4_mount_post();
        }

        // --- Subtract: M3 screw holes at 4 corners (through lid into body bosses) ---
        lid_boss_positions()
            translate([0, 0, -seal_lip - 0.1])
                cylinder(d = m3_hole, h = wall + seal_lip + 0.2);

        // --- Subtract: M4 holes in AP mount posts ---
        ap_pattern = 100;
        for (x = [-ap_pattern/2, ap_pattern/2])
            for (y = [-ap_pattern/2, ap_pattern/2])
                translate([x, y, -0.1])
                    cylinder(d = m4_hole, h = wall + m4_boss_h + 0.2);
    }
}

// =============================================================================
//  SUB-MODULES USED BY BODY AND LID
// =============================================================================

// --- HaLow module shelf with zip-tie slots ---
module halow_shelf() {
    shelf_w = halow_w + clearance * 2;
    shelf_d = halow_d + clearance * 2;
    shelf_t = 2;        // Shelf plate thickness
    rail_h  = 6;        // Side rail height

    // Shelf plate
    translate([0, 0, 0])
        cube([shelf_w, shelf_d, shelf_t], center = true);

    // Side rails
    for (sx = [-1, 1])
        translate([sx * (shelf_w/2 - 1), 0, shelf_t/2 + rail_h/2])
            cube([2, shelf_d, rail_h], center = true);

    // Zip-tie slots (2 pairs, through the shelf)
    zt_w = 4;       // Zip-tie slot width
    zt_d = 1.5;     // Zip-tie slot depth (thickness of tie)
    for (dy = [-shelf_d/4, shelf_d/4]) {
        for (sx = [-1, 1]) {
            translate([sx * (shelf_w/2 - 5), dy, 0])
                cube([zt_w, zt_d, shelf_t + 1], center = true);
        }
    }
}

// --- Oval cutout for cable pass-through ---
module oval_cutout(w, h, depth) {
    // Oval = hull of two circles
    hull() {
        translate([-(w - h)/2, 0, 0])
            cylinder(d = h, h = depth, center = true);
        translate([(w - h)/2, 0, 0])
            cylinder(d = h, h = depth, center = true);
    }
}

// --- Drip lip around cable pass-through (external) ---
module cable_drip_lip(w, h) {
    lip_t = 1.5;
    lip_drop = 3;
    // Small overhang below the oval cutout
    translate([0, 0, -h/2 - lip_drop/2])
        cube([w + 4, lip_t, lip_drop], center = true);
}

// --- M3 screw boss for lid attachment (inside body) ---
module lid_screw_boss_body() {
    difference() {
        cylinder(d = m3_boss_od, h = m3_boss_h);
        translate([0, 0, -0.1])
            cylinder(d = m3_hole * 0.85, h = m3_boss_h + 0.2);  // Pilot hole for self-tap
    }
}

// --- M4 AP mount post on lid ---
module m4_mount_post() {
    difference() {
        union() {
            cylinder(d = m4_boss_od, h = m4_boss_h);
            // Base reinforcement
            cylinder(d1 = m4_boss_od + 3, d2 = m4_boss_od, h = 2);
        }
        translate([0, 0, -0.1])
            cylinder(d = m4_hole, h = m4_boss_h + 0.2);
    }
}

// --- Lid screw boss positions (4 corners) ---
module lid_boss_positions() {
    inset = lid_boss_inset;
    for (x = [-int_w/2 + inset, int_w/2 - inset])
        for (y = [-int_d/2 + inset, int_d/2 - inset])
            translate([x, y, ext_h - m3_boss_h])
                children();
}

// =============================================================================
//  TOP-LEVEL RENDER SWITCH
// =============================================================================

if (part == "body") {
    body();
}
else if (part == "lid") {
    // Lid oriented for printing (flat side down)
    translate([0, 0, wall])
        rotate([180, 0, 0])
            lid();
}
else if (part == "assembly") {
    // Exploded assembly preview
    color("SteelBlue", 0.85)   body();
    color("OrangeRed", 0.75)   translate([0, 0, ext_h + 15]) lid();
}
else {
    echo("ERROR: set part to \"body\", \"lid\", or \"assembly\"");
}

// =============================================================================
//  BUILD VOLUME CHECK
// =============================================================================
// Bambu Lab P2S: 256 x 256 x 256 mm
echo(str("Exterior dimensions: ",
         ext_w, " x ", ext_d, " x ", ext_h, " mm"));
echo(str("Fits P2S bed (256x256x256): ",
         (ext_w <= 256 && ext_d <= 256 && ext_h <= 256) ? "YES" : "NO — rotate or split"));
