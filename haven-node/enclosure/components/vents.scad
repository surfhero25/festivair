// =============================================================================
// FestivAir Haven Node — Rain-Baffled Louver Vent Module
// =============================================================================
// Parametric angled louver vents that allow airflow while deflecting rain.
// Louvers are oriented at 45 degrees (printable without supports when the
// vent panel is part of a vertical wall printed upright).
// =============================================================================

// Default parameters
default_vent_w        = 60;     // Total vent opening width
default_vent_h        = 40;     // Total vent opening height
default_louver_count  = 6;      // Number of louver slats
default_louver_angle  = 45;     // Louver tilt angle (degrees)
default_louver_t      = 1.2;    // Louver slat thickness
default_wall_t        = 3;      // Surrounding wall thickness (depth of louver)
default_frame_w       = 2;      // Frame border around vent opening

// --------------------------------------------------------------------------
// Single louver slat — angled blade that spans the vent width
// Oriented so rain drips down the outer face; air passes through gaps.
// --------------------------------------------------------------------------
module louver_slat(width, depth, thickness, angle) {
    // The slat is a thin rectangle rotated by `angle` around its bottom edge.
    // At 45 degrees with depth = wall thickness, the slat just reaches
    // from front to back of the wall, creating an overlapping rain baffle.
    rotate([angle, 0, 0])
        cube([width, thickness, depth / cos(angle)]);
}

// --------------------------------------------------------------------------
// Louver vent panel — cut into a wall of given thickness
// origin = bottom-left of the outer vent frame
//
// Parameters:
//   w           — vent opening width (X)
//   h           — vent opening height (Z)
//   wall_t      — wall / louver depth (Y)
//   count       — number of louver slats
//   angle       — louver tilt (degrees, 0 = horizontal / closed)
//   slat_t      — slat material thickness
//   frame       — border frame width around the opening
// --------------------------------------------------------------------------
module louver_vent(w        = default_vent_w,
                   h        = default_vent_h,
                   wall_t   = default_wall_t,
                   count    = default_louver_count,
                   angle    = default_louver_angle,
                   slat_t   = default_louver_t,
                   frame    = default_frame_w) {

    // Derived
    opening_w = w - frame * 2;
    opening_h = h - frame * 2;
    pitch     = opening_h / count;    // Vertical pitch between slats

    union() {
        // --- Outer frame (solid border) ---
        difference() {
            cube([w, wall_t, h]);
            translate([frame, -0.1, frame])
                cube([opening_w, wall_t + 0.2, opening_h]);
        }

        // --- Louver slats ---
        for (i = [0 : count - 1]) {
            translate([frame, 0, frame + i * pitch])
                louver_slat(opening_w, wall_t, slat_t, angle);
        }

        // --- Top closing slat (prevents rain entry at top) ---
        translate([frame, 0, frame + count * pitch - slat_t])
            cube([opening_w, wall_t, slat_t]);
    }
}

// --------------------------------------------------------------------------
// Vent cutout tool — use this to subtract the vent opening from the wall,
// then union the louver_vent panel back in.  This is the "negative" shape.
// --------------------------------------------------------------------------
module louver_vent_cutout(w     = default_vent_w,
                          h     = default_vent_h,
                          wall_t = default_wall_t,
                          frame = default_frame_w) {
    // Slightly oversized for clean boolean subtraction
    translate([frame, -0.1, frame])
        cube([w - frame * 2, wall_t + 0.2, h - frame * 2]);
}

// --------------------------------------------------------------------------
// Combined convenience module: cuts the hole and fills with louvers
// Use inside a difference() on the wall, then union() this after.
// Or just place this; it includes its own frame.
// --------------------------------------------------------------------------
module vent_assembly(w       = default_vent_w,
                     h       = default_vent_h,
                     wall_t  = default_wall_t,
                     count   = default_louver_count,
                     angle   = default_louver_angle,
                     slat_t  = default_louver_t,
                     frame   = default_frame_w) {
    louver_vent(w, h, wall_t, count, angle, slat_t, frame);
}

// Preview when opened directly
vent_assembly();
