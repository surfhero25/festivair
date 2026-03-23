// =============================================================================
// FestivAir Haven Node — Battery Bay Module
// =============================================================================
// Retaining walls, cable routing channel, and restraint lip for LiFePO4 pack.
// Battery sits on the enclosure floor; this module adds the walls and guides.
// =============================================================================

// Default battery dimensions (overridden by main file parameters)
default_bat_w = 150;
default_bat_d = 65;
default_bat_h = 95;

// Bay parameters
bay_wall          = 2;      // Retaining wall thickness
bay_lip_h         = 8;      // Height of top retaining lip
bay_lip_inset     = 4;      // How far lip overhangs battery
bay_cable_slot_w  = 12;     // Cable routing slot width
bay_cable_slot_h  = 8;      // Cable routing slot height
bay_floor_pad     = 1;      // Anti-vibration pad recess depth

// --------------------------------------------------------------------------
// Battery retaining walls — U-shape (open on one side for cable routing)
// origin = center-bottom of battery footprint
// --------------------------------------------------------------------------
module battery_bay(bat_w = default_bat_w,
                   bat_d = default_bat_d,
                   bat_h = default_bat_h,
                   clearance = 2) {

    inner_w = bat_w + clearance;
    inner_d = bat_d + clearance;
    outer_w = inner_w + bay_wall * 2;
    outer_d = inner_d + bay_wall * 2;
    wall_h  = bat_h * 0.35;  // Walls ~35% of battery height (enough to retain)

    difference() {
        union() {
            // --- U-shaped retaining walls (3 sides) ---
            difference() {
                // Outer block
                translate([0, 0, wall_h/2])
                    cube([outer_w, outer_d, wall_h], center = true);
                // Inner cavity
                translate([0, 0, wall_h/2 + bay_wall])
                    cube([inner_w, inner_d, wall_h], center = true);
                // Open the front face (-Y side) for cable access
                translate([0, -(outer_d/2 + 1), wall_h/2])
                    cube([inner_w - 20, bay_wall + 2, wall_h + 2], center = true);
            }

            // --- Top retaining lips (2 opposing sides, left + right) ---
            for (sx = [-1, 1]) {
                translate([sx * (inner_w/2 - bay_lip_inset/2), 0, wall_h])
                    cube([bay_lip_inset, inner_d * 0.4, bay_lip_h], center = false);
            }

            // --- Corner gussets for strength (4 corners, 45-degree triangles) ---
            gusset = 8;
            for (sx = [-1, 1])
                for (sy = [-1, 1])
                    translate([sx * (inner_w/2 + bay_wall/2),
                               sy * (inner_d/2 + bay_wall/2), 0])
                        rotate([0, 0, (sx > 0 ? (sy > 0 ? 180 : 270) : (sy > 0 ? 90 : 0))])
                            linear_extrude(height = wall_h)
                                polygon([[0, 0], [gusset, 0], [0, gusset]]);
        }

        // --- Cable routing slot through back wall (+Y side) ---
        translate([0, (inner_d/2 + bay_wall/2), bay_cable_slot_h/2])
            cube([bay_cable_slot_w, bay_wall + 2, bay_cable_slot_h], center = true);

        // --- Anti-vibration pad recess in floor ---
        translate([0, 0, -0.1])
            rounded_rect_cutout(bat_w - 10, bat_d - 10, bay_floor_pad + 0.1, r = 3);
    }
}

// --------------------------------------------------------------------------
// Helper: rounded rectangle cutout (for pad recess)
// --------------------------------------------------------------------------
module rounded_rect_cutout(w, d, h, r = 3) {
    translate([0, 0, h/2])
        minkowski() {
            cube([w - 2*r, d - 2*r, h/2], center = true);
            cylinder(r = r, h = h/2, $fn = 30);
        }
}

// --------------------------------------------------------------------------
// Cable guide clip — snap-on cable routing along the floor
// --------------------------------------------------------------------------
module cable_guide(slot_w = 6, slot_h = 4, length = 20) {
    difference() {
        cube([length, slot_w + 4, slot_h + 3], center = true);
        // Channel
        translate([0, 0, 1.5])
            cube([length + 1, slot_w, slot_h], center = true);
        // Entry slot
        translate([0, 0, slot_h/2 + 2])
            cube([length + 1, slot_w * 0.6, slot_h], center = true);
    }
}

// Preview when opened directly
battery_bay();
