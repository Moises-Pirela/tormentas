package main

import "core:fmt"

Engine_Principle :: enum u8 {
    Deterministic,
    Data_Oriented,
    Procedural_First,
    Hot_Reloadable,
    Runtime_Inspectable,
    Incrementally_Regeneratable,
}

Region_Purpose :: enum u8 {
    Transit,
    Habitat,
    Industry,
    Maintenance,
    Combat_Gate,
}

Scale_Class :: enum u8 {
    Human,
    Industrial,
    Monumental,
    Incomprehensible,
}

Encounter_Intent :: enum u8 {
    Quiet_Traversal,
    Probe_And_Retreat,
    Mid_Range_Crossfire,
    Flank_Pressure,
    Defensive_Hold,
}

Landmark_Spec :: struct {
    name:        string,
    role:        string,
    scale:       Scale_Class,
    critical:    bool,
}

Combat_Space_Spec :: struct {
    name:            string,
    intent:          Encounter_Intent,
    cover_density:   f32,
    verticality:      f32,
    backtrack_value:  f32,
}

Region_Spec :: struct {
    name:               string,
    seed:               u64,
    purpose:            Region_Purpose,
    scale:              Scale_Class,
    dominant_materials: [8]string,
    landmarks:          [8]Landmark_Spec,
    landmark_count:     int,
    combat_spaces:      [8]Combat_Space_Spec,
    combat_space_count: int,
}

Generator_Trace :: struct {
    source_name: string,
    source_seed: u64,
    rule_count:  int,
    notes:       [8]string,
    note_count:  int,
}

Project_Seed :: struct {
    seed:            u64,
    principles:      [8]Engine_Principle,
    principle_count: int,
    regions:         [8]Region_Spec,
    region_count:    int,
}

project_add_principle :: proc(project: ^Project_Seed, principle: Engine_Principle) {
    if project.principle_count >= len(project.principles) {
        return
    }
    project.principles[project.principle_count] = principle
    project.principle_count += 1
}

project_add_region :: proc(project: ^Project_Seed, region: Region_Spec) {
    if project.region_count >= len(project.regions) {
        return
    }
    project.regions[project.region_count] = region
    project.region_count += 1
}

trace_add_note :: proc(trace: ^Generator_Trace, note: string) {
    if trace.note_count >= len(trace.notes) {
        return
    }
    trace.notes[trace.note_count] = note
    trace.note_count += 1
}

make_project_seed :: proc(seed: u64) -> Project_Seed {
    project := Project_Seed{seed = seed}
    core_spine_seed := seed ~ u64(0xC05E5EED)

    project_add_principle(&project, .Deterministic)
    project_add_principle(&project, .Data_Oriented)
    project_add_principle(&project, .Procedural_First)
    project_add_principle(&project, .Hot_Reloadable)
    project_add_principle(&project, .Runtime_Inspectable)

    core_spine := Region_Spec{
        name    = "Core Spine",
        seed    = core_spine_seed,
        purpose = .Transit,
        scale   = .Monumental,
        landmark_count = 2,
        combat_space_count = 2,
    }
    core_spine.dominant_materials[0] = "ribbed_concrete"
    core_spine.dominant_materials[1] = "oxidized_steel"
    core_spine.dominant_materials[2] = "ceramic_service_tile"

    core_spine.landmarks[0] = Landmark_Spec{
        name     = "Elevator Well 7",
        role     = "long-range vertical navigation reference",
        scale    = .Incomprehensible,
        critical = true,
    }
    core_spine.landmarks[1] = Landmark_Spec{
        name     = "Collapsed Heat Exchange",
        role     = "optional combat route and backtrack shortcut",
        scale    = .Industrial,
        critical = false,
    }

    core_spine.combat_spaces[0] = Combat_Space_Spec{
        name            = "Bridge Maintenance Deck",
        intent          = .Mid_Range_Crossfire,
        cover_density   = 0.42,
        verticality     = 0.35,
        backtrack_value = 0.65,
    }
    core_spine.combat_spaces[1] = Combat_Space_Spec{
        name            = "Service Sluice",
        intent          = .Probe_And_Retreat,
        cover_density   = 0.22,
        verticality     = 0.15,
        backtrack_value = 0.30,
    }

    project_add_region(&project, core_spine)
    return project
}

generate_region_trace :: proc(region: Region_Spec) -> Generator_Trace {
    trace := Generator_Trace{
        source_name = region.name,
        source_seed = region.seed,
        rule_count  = 0,
    }

    trace_add_note(&trace, "Read semantic region intent before generating geometry.")
    trace.rule_count += 1

    if region.scale == .Monumental || region.scale == .Incomprehensible {
        trace_add_note(&trace, "Reserve oversized structural spans before adding human-scale paths.")
        trace.rule_count += 1
    }

    if region.combat_space_count > 0 {
        trace_add_note(&trace, "Generate traversal and sightlines from combat-space intent.")
        trace.rule_count += 1
    }

    if region.landmark_count > 0 {
        trace_add_note(&trace, "Place landmarks as navigation anchors before detail passes.")
        trace.rule_count += 1
    }

    return trace
}

dump_project_seed :: proc(project: ^Project_Seed) {
    fmt.printf("megastructure_fps seed=%d\n", project.seed)
    fmt.println("principles:")
    for i in 0..<project.principle_count {
        fmt.printf("  - %v\n", project.principles[i])
    }

    fmt.println("regions:")
    for i in 0..<project.region_count {
        region := project.regions[i]
        fmt.printf("  - %s purpose=%v scale=%v\n", region.name, region.purpose, region.scale)

        trace := generate_region_trace(region)
        fmt.printf("    generator seed=%d rules=%d\n", trace.source_seed, trace.rule_count)
        for note_index in 0..<trace.note_count {
            fmt.printf("    trace: %s\n", trace.notes[note_index])
        }
    }
}
