// =============================================================================
// FestivAir Haven Node — Tripod Mount & Pole Clamp Adapter
// =============================================================================
// 1/4"-20 UNC heat-set insert boss for standard tripod / camera mounts
// 35mm pole clamp adapter with M6 bolt holes for festival pole deployment
// =============================================================================

// --- 1/4"-20 Heat-Set Insert Parameters ---
// Standard brass heat-set insert for 1/4"-20: OD ~6.3mm, length ~6.35mm
insert_od       = 6.3;      // Heat-set insert outer diameter
insert_depth    = 8;         // Hole depth (slightly deeper than insert)
boss_od         = 14;        // Boss outer diameter (structural)
boss_h          = 10;        // Boss total height
boss_fillet     = 2;         // Base fillet radius

// --- 35mm Pole Clamp Parameters ---
pole_dia        = 35;        // Target pole diameter
clamp_thickness = 4;         // Clamp wall thickness
clamp_width     = 30;        // Clamp width (along pole axis)
clamp_gap       = 3;         // Gap for bolt clamping
tab_w           = 18;        // Bolt tab width
tab_h           = 20;        // Bolt tab height from clamp OD
m6_hole         = 6.5;       // M6 bolt clearance hole

// --------------------------------------------------------------------------
// 1/4"-20 heat-set insert boss
// Sits on the bottom face of the enclosure; printed boss-up so the
// cylinder is on the build plate (no supports needed).
// --------------------------------------------------------------------------
module tripod_boss() {
    difference() {
        union() {
            // Main boss cylinder
            cylinder(d = boss_od, h = boss_h, $fn = 60);
            // Base reinforcement fillet (45-degree cone = printable)
            cylinder(d1 = boss_od + boss_fillet * 2,
                     d2 = boss_od,
                     h  = boss_fillet, $fn = 60);
        }
        // Heat-set insert hole (from top, blind hole)
        translate([0, 0, boss_h - insert_depth])
            cylinder(d = insert_od, h = insert_depth + 0.1, $fn = 60);
    }
}

// --------------------------------------------------------------------------
// 35mm pole clamp — C-clamp with bolt tabs
// Mounts to the back face of the enclosure via integrated attachment tabs.
// Clamp opens at the bottom; two M6 bolts squeeze it shut.
// --------------------------------------------------------------------------
module pole_clamp() {
    clamp_or = pole_dia / 2 + clamp_thickness;
    clamp_ir = pole_dia / 2;

    difference() {
        union() {
            // --- C-clamp body ---
            difference() {
                // Outer cylinder
                cylinder(r = clamp_or, h = clamp_width, $fn = 60);
                // Inner bore
                translate([0, 0, -0.1])
                    cylinder(r = clamp_ir, h = clamp_width + 0.2, $fn = 60);
                // Opening gap at bottom (-Y)
                translate([-clamp_gap/2, -(clamp_or + 1), -0.1])
                    cube([clamp_gap, clamp_or + 1, clamp_width + 0.2]);
            }

            // --- Bolt tabs (two flanges at the gap) ---
            for (sx = [-1, 1]) {
                translate([sx * (clamp_gap/2 + tab_w/2), -(clamp_or), 0])
                    difference() {
                        // Tab body
                        cube([tab_w, tab_h, clamp_width], center = false);
                        // Bolt hole
                        translate([tab_w/2, tab_h/2, -0.1])
                            cylinder(d = m6_hole, h = clamp_width + 0.2, $fn = 60);
                    }
            }
        }

        // Flatten the back face (+Y) for mounting flush against enclosure
        translate([-(clamp_or + 1), clamp_ir + clamp_thickness * 0.3, -0.1])
            cube([clamp_or * 2 + 2, clamp_or, clamp_width + 0.2]);
    }
}

// --------------------------------------------------------------------------
// Enclosure mounting tabs — attach pole clamp to enclosure back wall
// Two tabs with M6 bolt holes, spaced to match enclosure screw bosses
// --------------------------------------------------------------------------
module clamp_mount_tabs(spacing = 60, wall_t = 3) {
    tab_thickness = wall_t;
    tab_size      = 16;

    for (sx = [-1, 1]) {
        translate([sx * spacing/2, 0, 0])
            difference() {
                // Tab body
                cube([tab_size, tab_thickness, tab_size], center = true);
                // M6 bolt hole through tab
                rotate([90, 0, 0])
                    cylinder(d = m6_hole, h = tab_thickness + 1, center = true, $fn = 60);
            }
    }
}

// --------------------------------------------------------------------------
// Complete pole mount assembly (clamp + attachment interface)
// --------------------------------------------------------------------------
module pole_mount_assembly() {
    // Clamp, oriented so the flat back faces +Y
    pole_clamp();

    // Attachment tabs at the flat back
    clamp_or = pole_dia / 2 + clamp_thickness;
    translate([0, clamp_or * 0.3 + 1.5, clamp_width / 2])
        rotate([90, 0, 0])
            clamp_mount_tabs();
}

// Preview when opened directly
translate([0, 0, 0])   tripod_boss();
translate([40, 0, 0])  pole_mount_assembly();
