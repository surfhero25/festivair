// =============================================================================
// FestivAir Haven Node — Raspberry Pi 5 Mounting Plate
// =============================================================================
// Standalone module for Pi 5 mounting with M2.5 standoffs.
// Pi 5 hole pattern: 58mm x 49mm (center-to-center)
// =============================================================================

// Standoff parameters
standoff_od     = 6;        // Outer diameter of standoff
standoff_id     = 2.5;      // M2.5 through-hole diameter (+ slight clearance)
standoff_h      = 5;        // Standoff height (clearance under PCB)
standoff_base   = 1.5;      // Reinforcement base fillet height

// Pi 5 mounting hole pattern (center-to-center)
pi_hole_x = 58;
pi_hole_y = 49;

// --------------------------------------------------------------------------
// Single M2.5 standoff with reinforcement base
// --------------------------------------------------------------------------
module m25_standoff(h = standoff_h) {
    difference() {
        union() {
            // Main post
            cylinder(d = standoff_od, h = h, $fn = 60);
            // Base reinforcement — slight taper for print-without-support
            cylinder(d1 = standoff_od + 2, d2 = standoff_od, h = standoff_base, $fn = 60);
        }
        // M2.5 hole all the way through
        translate([0, 0, -0.1])
            cylinder(d = standoff_id, h = h + 0.2, $fn = 60);
    }
}

// --------------------------------------------------------------------------
// Pi 5 mounting plate — 4 standoffs at the official hole pattern
// origin = center of the 4-hole rectangle
// --------------------------------------------------------------------------
module pi5_mount(standoff_height = standoff_h) {
    for (x = [-pi_hole_x/2, pi_hole_x/2])
        for (y = [-pi_hole_y/2, pi_hole_y/2])
            translate([x, y, 0])
                m25_standoff(h = standoff_height);
}

// --------------------------------------------------------------------------
// Optional: thin alignment plate connecting the 4 standoffs (for standalone
// printing / testing).  Not used in main enclosure — standoffs grow from floor.
// --------------------------------------------------------------------------
module pi5_mount_plate(plate_t = 2, standoff_height = standoff_h) {
    plate_w = pi_hole_x + standoff_od + 4;
    plate_d = pi_hole_y + standoff_od + 4;

    union() {
        // Base plate with rounded corners
        translate([0, 0, plate_t/2])
            minkowski() {
                cube([plate_w - 4, plate_d - 4, plate_t/2], center = true);
                cylinder(r = 2, h = plate_t/2, $fn = 30);
            }
        // Standoffs on top of plate
        translate([0, 0, plate_t])
            pi5_mount(standoff_height);
    }
}

// Preview when opened directly
pi5_mount_plate();
