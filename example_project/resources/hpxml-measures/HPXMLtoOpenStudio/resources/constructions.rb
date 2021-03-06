# frozen_string_literal: true

class Constructions
  # Container class for walls, floors/ceilings, roofs, etc.

  def self.apply_wood_stud_wall(runner, model, surfaces, wall, constr_name,
                                cavity_r, install_grade, cavity_depth_in, cavity_filled,
                                framing_factor, drywall_thick_in, osb_thick_in,
                                rigid_r, mat_ext_finish, otherside_drywall_thick_in,
                                inside_film, outside_film)

    return if surfaces.empty?

    # Define materials
    if cavity_r > 0
      if cavity_filled
        # Insulation
        mat_cavity = Material.new(name = nil, thick_in = cavity_depth_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth_in / cavity_r)
      else
        # Insulation plus air gap when insulation thickness < cavity depth
        mat_cavity = Material.new(name = nil, thick_in = cavity_depth_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth_in / (cavity_r + Gas.AirGapRvalue))
      end
    else
      # Empty cavity
      mat_cavity = Material.AirCavityClosed(cavity_depth_in)
    end
    mat_framing = Material.new(name = nil, thick_in = cavity_depth_in, mat_base = BaseMaterial.Wood)
    mat_gap = Material.AirCavityClosed(cavity_depth_in)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [framing_factor, 1 - framing_factor - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if otherside_drywall_thick_in > 0 # E.g., interior partition wall
      constr.add_layer(Material.GypsumWall(otherside_drywall_thick_in))
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    constr.add_layer([mat_framing, mat_cavity, mat_gap], 'WallStudAndCavity')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    if not wall.nil?
      wall.insulation_cavity_r_value = cavity_r
      wall.insulation_continuous_r_value = rigid_r
    end
  end

  def self.apply_double_stud_wall(runner, model, surfaces, wall, constr_name,
                                  cavity_r, install_grade, stud_depth_in, gap_depth_in,
                                  framing_factor, framing_spacing, is_staggered,
                                  drywall_thick_in, osb_thick_in, rigid_r,
                                  mat_ext_finish, inside_film, outside_film)

    return if surfaces.empty?

    # Define materials
    cavity_depth_in = 2.0 * stud_depth_in + gap_depth_in
    mat_ins_inner_outer = Material.new(name = nil, thick_in = stud_depth_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth_in / cavity_r)
    mat_ins_middle = Material.new(name = nil, thick_in = gap_depth_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth_in / cavity_r)
    mat_framing_inner_outer = Material.new(name = nil, thick_in = stud_depth_in, mat_base = BaseMaterial.Wood)
    mat_framing_middle = Material.new(name = nil, thick_in = gap_depth_in, mat_base = BaseMaterial.Wood)
    mat_stud = Material.new(name = nil, thick_in = stud_depth_in, mat_base = BaseMaterial.Wood)
    mat_gap_total = Material.AirCavityClosed(cavity_depth_in)
    mat_gap_inner_outer = Material.new(name = nil, thick_in = stud_depth_in, mat_base = nil, k_in = stud_depth_in / (mat_gap_total.rvalue * stud_depth_in / cavity_depth_in), rho = Gas.Air.rho, cp = Gas.Air.cp)
    mat_gap_middle = Material.new(name = nil, thick_in = gap_depth_in, mat_base = nil, k_in = gap_depth_in / (mat_gap_total.rvalue * gap_depth_in / cavity_depth_in), rho = Gas.Air.rho, cp = Gas.Air.cp)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    stud_frac = 1.5 / framing_spacing
    misc_framing_factor = framing_factor - stud_frac
    if misc_framing_factor < 0
      fail "Framing Factor (#{framing_factor}) is less than the framing solely provided by the studs (#{stud_frac})."
    end

    dsGapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [misc_framing_factor, stud_frac, stud_frac, dsGapFactor, (1.0 - (2 * stud_frac + misc_framing_factor + dsGapFactor))]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    if is_staggered
      constr.add_layer([mat_framing_inner_outer, mat_ins_inner_outer, mat_stud, mat_gap_inner_outer, mat_ins_inner_outer], 'WallStudandCavityOuter')
    else
      constr.add_layer([mat_framing_inner_outer, mat_stud, mat_ins_inner_outer, mat_gap_inner_outer, mat_ins_inner_outer], 'WallStudandCavityOuter')
    end
    if gap_depth_in > 0
      constr.add_layer([mat_framing_middle, mat_ins_middle, mat_ins_middle, mat_gap_middle, mat_ins_middle], 'WallCavity')
    end
    constr.add_layer([mat_framing_inner_outer, mat_stud, mat_ins_inner_outer, mat_gap_inner_outer, mat_ins_inner_outer], 'WallStudandCavityInner')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    wall.insulation_continuous_r_value = rigid_r
  end

  def self.apply_cmu_wall(runner, model, surfaces, wall, constr_name,
                          thick_in, conductivity, density, framing_factor,
                          furring_r, furring_cavity_depth, furring_spacing,
                          drywall_thick_in, osb_thick_in, rigid_r,
                          mat_ext_finish, inside_film, outside_film)

    return if surfaces.empty?

    # Define materials
    mat_cmu = Material.new(name = nil, thick_in = thick_in, mat_base = BaseMaterial.Concrete, k_in = conductivity, rho = density)
    mat_framing = Material.new(name = nil, thick_in = thick_in, mat_base = BaseMaterial.Wood)
    mat_furring = nil
    mat_furring_cavity = nil
    if furring_cavity_depth != 0
      mat_furring = Material.new(name = nil, thick_in = furring_cavity_depth, mat_base = BaseMaterial.Wood)
      if furring_r == 0
        mat_furring_cavity = Material.AirCavityClosed(furring_cavity_depth)
      else
        mat_furring_cavity = Material.new(name = nil, thick_in = furring_cavity_depth, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = furring_cavity_depth / furring_r)
      end
    end
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    if not mat_furring.nil?
      stud_frac = 1.5 / furring_spacing
      cavity_frac = 1.0 - (stud_frac + framing_factor)
      path_fracs = [framing_factor, stud_frac, cavity_frac]
    else # No furring:
      path_fracs = [framing_factor, 1.0 - framing_factor]
    end

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    if not mat_furring.nil?
      constr.add_layer([mat_framing, mat_cmu, mat_cmu], 'WallCMU')
      constr.add_layer([mat_furring, mat_furring, mat_furring_cavity], 'WallFurring')
    else
      constr.add_layer([mat_framing, mat_cmu], 'WallCMU')
    end
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    wall.insulation_cavity_r_value = furring_r
    wall.insulation_continuous_r_value = rigid_r
  end

  def self.apply_icf_wall(runner, model, surfaces, wall, constr_name,
                          icf_r, ins_thick_in, concrete_thick_in, framing_factor,
                          drywall_thick_in, osb_thick_in, rigid_r,
                          mat_ext_finish, inside_film, outside_film)

    return if surfaces.empty?

    # Define materials
    mat_ins = Material.new(name = nil, thick_in = ins_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = ins_thick_in / icf_r)
    mat_conc = Material.new(name = nil, thick_in = concrete_thick_in, mat_base = BaseMaterial.Concrete)
    mat_framing_inner_outer = Material.new(name = nil, thick_in = ins_thick_in, mat_base = BaseMaterial.Wood)
    mat_framing_middle = Material.new(name = nil, thick_in = concrete_thick_in, mat_base = BaseMaterial.Wood)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    path_fracs = [framing_factor, 1.0 - framing_factor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    constr.add_layer([mat_framing_inner_outer, mat_ins], 'WallICFInsFormOuter')
    constr.add_layer([mat_framing_middle, mat_conc], 'WallICFConcrete')
    constr.add_layer([mat_framing_inner_outer, mat_ins], 'WallICFInsFormInner')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    wall.insulation_continuous_r_value = rigid_r
  end

  def self.apply_sip_wall(runner, model, surfaces, wall, constr_name, sip_r,
                          sip_thick_in, framing_factor, sheathing_thick_in,
                          drywall_thick_in, osb_thick_in, rigid_r,
                          mat_ext_finish, inside_film, outside_film)

    return if surfaces.empty?

    # Define materials
    spline_thick_in = 0.5
    ins_thick_in = sip_thick_in - (2.0 * spline_thick_in) # in
    mat_int_sheath = Material.new(name = 'WallIntSheathing', thick_in = sheathing_thick_in, mat_base = BaseMaterial.Wood)
    mat_framing_inner_outer = Material.new(name = nil, thick_in = spline_thick_in, mat_base = BaseMaterial.Wood)
    mat_framing_middle = Material.new(name = nil, thick_in = ins_thick_in, mat_base = BaseMaterial.Wood)
    mat_spline = Material.new(name = nil, thick_in = spline_thick_in, mat_base = BaseMaterial.Wood)
    mat_ins_inner_outer = Material.new(name = nil, thick_in = spline_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = sip_thick_in / sip_r)
    mat_ins_middle = Material.new(name = nil, thick_in = ins_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = sip_thick_in / sip_r)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    spline_frac = 4.0 / 48.0 # One 4" spline for every 48" wide panel
    cavity_frac = 1.0 - (spline_frac + framing_factor)
    path_fracs = [framing_factor, spline_frac, cavity_frac]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    constr.add_layer([mat_framing_inner_outer, mat_spline, mat_ins_inner_outer], 'WallSplineLayerOuter')
    constr.add_layer([mat_framing_middle, mat_ins_middle, mat_ins_middle], 'WallIns')
    constr.add_layer([mat_framing_inner_outer, mat_spline, mat_ins_inner_outer], 'WallSplineLayerInner')
    constr.add_layer(mat_int_sheath)
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)
  end

  def self.apply_steel_stud_wall(runner, model, surfaces, wall, constr_name,
                                 cavity_r, install_grade, cavity_depth,
                                 cavity_filled, framing_factor, correction_factor,
                                 drywall_thick_in, osb_thick_in, rigid_r,
                                 mat_ext_finish, inside_film, outside_film)

    return if surfaces.empty?

    # Define materials
    eR = cavity_r * correction_factor # The effective R-value of the cavity insulation with steel stud framing
    if eR > 0
      if cavity_filled
        # Insulation
        mat_cavity = Material.new(name = nil, thick_in = cavity_depth, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth / eR)
      else
        # Insulation plus air gap when insulation thickness < cavity depth
        mat_cavity = Material.new(name = nil, thick_in = cavity_depth, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth / (eR + Gas.AirGapRvalue))
      end
    else
      # Empty cavity
      mat_cavity = Material.AirCavityClosed(cavity_depth)
    end
    mat_gap = Material.AirCavityClosed(cavity_depth)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [1 - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    constr.add_layer([mat_cavity, mat_gap], 'WallStudAndCavity')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    wall.insulation_cavity_r_value = cavity_r
    wall.insulation_continuous_r_value = rigid_r
  end

  def self.apply_generic_layered_wall(runner, model, surfaces, wall, constr_name,
                                      thick_ins, conds, denss, specheats,
                                      drywall_thick_in, osb_thick_in, rigid_r,
                                      mat_ext_finish, inside_film, outside_film)

    return if surfaces.empty?

    # Validate inputs
    for idx in 0..4
      if (thick_ins[idx].nil? != conds[idx].nil?) || (thick_ins[idx].nil? != denss[idx].nil?) || (thick_ins[idx].nil? != specheats[idx].nil?)
        fail "Layer #{idx + 1} does not have all four properties (thickness, conductivity, density, specific heat) entered."
      end
    end

    # Define materials
    mats = []
    mats << Material.new(name = 'WallLayer1', thick_in = thick_ins[0], mat_base = nil, k_in = conds[0], rho = denss[0], cp = specheats[0])
    if not thick_ins[1].nil?
      mats << Material.new(name = 'WallLayer2', thick_in = thick_ins[1], mat_base = nil, k_in = conds[1], rho = denss[1], cp = specheats[1])
    end
    if not thick_ins[2].nil?
      mats << Material.new(name = 'WallLayer3', thick_in = thick_ins[2], mat_base = nil, k_in = conds[2], rho = denss[2], cp = specheats[2])
    end
    if not thick_ins[3].nil?
      mats << Material.new(name = 'WallLayer4', thick_in = thick_ins[3], mat_base = nil, k_in = conds[3], rho = denss[3], cp = specheats[3])
    end
    if not thick_ins[4].nil?
      mats << Material.new(name = 'WallLayer5', thick_in = thick_ins[4], mat_base = nil, k_in = conds[4], rho = denss[4], cp = specheats[4])
    end
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'WallSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'WallRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    path_fracs = [1]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    mats.each do |mat|
      constr.add_layer(mat)
    end
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    wall.insulation_continuous_r_value = rigid_r
  end

  def self.apply_rim_joist(runner, model, surfaces, rim_joist, constr_name,
                           cavity_r, install_grade, framing_factor,
                           drywall_thick_in, osb_thick_in,
                           rigid_r, mat_ext_finish, inside_film,
                           outside_film)

    return if surfaces.empty?

    # Define materials
    rim_joist_thick_in = 1.5
    sill_plate_thick_in = 3.5
    framing_thick_in = sill_plate_thick_in - rim_joist_thick_in # Extra non-continuous wood beyond rim joist thickness
    if cavity_r > 0
      # Insulation
      mat_cavity = Material.new(name = nil, thick_in = framing_thick_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = framing_thick_in / cavity_r)
    else
      # Empty cavity
      mat_cavity = Material.AirCavityOpen(framing_thick_in)
    end
    mat_framing = Material.new(name = nil, thick_in = framing_thick_in, mat_base = BaseMaterial.Wood)
    mat_gap = Material.AirCavityClosed(framing_thick_in)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'RimJoistSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'RimJoistRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [framing_factor, 1 - framing_factor - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_ext_finish.nil?
      constr.add_layer(mat_ext_finish)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    constr.add_layer([mat_framing, mat_cavity, mat_gap], 'RimJoistStudAndCavity')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)

    # Store info for HVAC Sizing measure
    rim_joist.insulation_continuous_r_value = rigid_r
    rim_joist.insulation_cavity_r_value = cavity_r
  end

  def self.apply_open_cavity_roof(runner, model, surfaces, constr_name,
                                  cavity_r, install_grade, cavity_ins_thick_in,
                                  framing_factor, framing_thick_in,
                                  osb_thick_in, rigid_r,
                                  mat_roofing, has_radiant_barrier,
                                  inside_film, outside_film, radiant_barrier_grade)

    return if surfaces.empty?

    # Define materials
    roof_ins_thickness_in = [cavity_ins_thick_in, framing_thick_in].max
    if cavity_r == 0
      mat_cavity = Material.AirCavityOpen(roof_ins_thickness_in)
    else
      cavity_k = cavity_ins_thick_in / cavity_r
      if cavity_ins_thick_in < framing_thick_in
        cavity_k = cavity_k * framing_thick_in / cavity_ins_thick_in
      end
      mat_cavity = Material.new(name = nil, thick_in = roof_ins_thickness_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_k)
    end
    if (cavity_ins_thick_in > framing_thick_in) && (framing_thick_in > 0)
      wood_k = BaseMaterial.Wood.k_in * cavity_ins_thick_in / framing_thick_in
    else
      wood_k = BaseMaterial.Wood.k_in
    end
    mat_framing = Material.new(name = nil, thick_in = roof_ins_thickness_in, mat_base = BaseMaterial.Wood, k_in = wood_k)
    mat_gap = Material.AirCavityOpen(roof_ins_thickness_in)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'RoofSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'RoofRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end
    mat_rb = nil
    if has_radiant_barrier
      mat_rb = Material.RadiantBarrier(radiant_barrier_grade)
    end

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [framing_factor, 1 - framing_factor - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_roofing.nil?
      constr.add_layer(mat_roofing)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    if framing_thick_in > 0
      constr.add_layer([mat_framing, mat_cavity, mat_gap], 'RoofStudAndCavity')
    end
    if not mat_rb.nil?
      constr.add_layer(mat_rb)
    end
    constr.add_layer(inside_film)

    # Create and assign construction to roof surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)
  end

  def self.apply_closed_cavity_roof(runner, model, surfaces, constr_name,
                                    cavity_r, install_grade, cavity_depth,
                                    filled_cavity, framing_factor, drywall_thick_in,
                                    osb_thick_in, rigid_r, mat_roofing, has_radiant_barrier,
                                    inside_film, outside_film, radiant_barrier_grade)

    return if surfaces.empty?

    # Define materials
    if cavity_r > 0
      if filled_cavity
        # Insulation
        mat_cavity = Material.new(name = nil, thick_in = cavity_depth, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth / cavity_r)
      else
        # Insulation plus air gap when insulation thickness < cavity depth
        mat_cavity = Material.new(name = nil, thick_in = cavity_depth, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = cavity_depth / (cavity_r + Gas.AirGapRvalue))
      end
    else
      # Empty cavity
      mat_cavity = Material.AirCavityClosed(cavity_depth)
    end
    mat_framing = Material.new(name = nil, thick_in = cavity_depth, mat_base = BaseMaterial.Wood)
    mat_gap = Material.AirCavityClosed(cavity_depth)
    mat_osb = nil
    if osb_thick_in > 0
      mat_osb = Material.new(name = 'RoofSheathing', thick_in = osb_thick_in, mat_base = BaseMaterial.Wood)
    end
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'RoofRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end
    mat_rb = nil
    if has_radiant_barrier
      mat_rb = Material.RadiantBarrier(radiant_barrier_grade)
    end

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [framing_factor, 1 - framing_factor - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_roofing.nil?
      constr.add_layer(mat_roofing)
    end
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_osb.nil?
      constr.add_layer(mat_osb)
    end
    constr.add_layer([mat_framing, mat_cavity, mat_gap], 'RoofStudAndCavity')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    if not mat_rb.nil?
      constr.add_layer(mat_rb)
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)
  end

  def self.apply_ceiling(runner, model, surfaces, constr_name,
                         cavity_r, install_grade, ins_thick_in,
                         framing_factor, joist_height_in,
                         drywall_thick_in, inside_film, outside_film)

    # Drywall below, open cavity above (e.g., attic floor)

    return if surfaces.empty?

    # Define materials
    mat_addtl_ins = nil
    if ins_thick_in >= joist_height_in
      # If the ceiling insulation thickness is greater than the joist thickness
      cavity_k = ins_thick_in / cavity_r
      if ins_thick_in > joist_height_in
        # If there is additional insulation beyond the rafter height,
        # these inputs are used for defining an additional layer
        mat_addtl_ins = Material.new(name = 'CeilingAdditionalIns', thick_in = (ins_thick_in - joist_height_in), mat_base = BaseMaterial.InsulationGenericLoosefill, k_in = cavity_k)
      end
      mat_cavity = Material.new(name = nil, thick_in = joist_height_in, mat_base = BaseMaterial.InsulationGenericLoosefill, k_in = cavity_k)
    else
      # Else the joist thickness is greater than the ceiling insulation thickness
      if cavity_r == 0
        mat_cavity = Material.AirCavityOpen(joist_height_in)
      else
        mat_cavity = Material.new(name = nil, thick_in = joist_height_in, mat_base = BaseMaterial.InsulationGenericLoosefill, k_in = joist_height_in / cavity_r)
      end
    end
    mat_framing = Material.new(name = nil, thick_in = joist_height_in, mat_base = BaseMaterial.Wood)
    mat_gap = Material.AirCavityOpen(joist_height_in)

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [framing_factor, 1 - framing_factor - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    if not mat_addtl_ins.nil?
      constr.add_layer(mat_addtl_ins)
    end
    constr.add_layer([mat_framing, mat_cavity, mat_gap], 'CeilingStudAndCavity')
    if drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(drywall_thick_in))
    end
    constr.add_layer(inside_film)

    # Create and assign construction to ceiling surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)
  end

  def self.apply_floor(runner, model, surfaces, constr_name,
                       cavity_r, install_grade,
                       framing_factor, joist_height_in,
                       plywood_thick_in, rigid_r, mat_floor_covering,
                       inside_film, outside_film)

    # Open cavity below, floor covering above (e.g., crawlspace ceiling)

    return if surfaces.empty?

    # Define materials
    mat_2x = Material.Stud2x(joist_height_in)
    if cavity_r == 0
      mat_cavity = Material.AirCavityOpen(mat_2x.thick_in)
    else
      mat_cavity = Material.new(name = nil, thick_in = mat_2x.thick_in, mat_base = BaseMaterial.InsulationGenericDensepack, k_in = mat_2x.thick_in / cavity_r)
    end
    mat_framing = Material.new(name = nil, thick_in = mat_2x.thick_in, mat_base = BaseMaterial.Wood)
    mat_gap = Material.AirCavityOpen(joist_height_in)
    mat_rigid = nil
    if rigid_r > 0
      rigid_thick_in = rigid_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'FloorRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / rigid_r)
    end

    # Set paths
    gapFactor = get_gap_factor(install_grade, framing_factor, cavity_r)
    path_fracs = [framing_factor, 1 - framing_factor - gapFactor, gapFactor]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(outside_film)
    constr.add_layer([mat_framing, mat_cavity, mat_gap], 'FloorStudAndCavity')
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if plywood_thick_in > 0
      constr.add_layer(Material.Plywood(plywood_thick_in))
    end
    if not mat_floor_covering.nil?
      constr.add_layer(mat_floor_covering)
    end
    constr.add_layer(inside_film)

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, surfaces, model)
  end

  def self.apply_foundation_wall(runner, model, wall_surfaces, wall_constr_name,
                                 ext_rigid_ins_offset, int_rigid_ins_offset, ext_rigid_ins_height,
                                 int_rigid_ins_height, ext_rigid_r, int_rigid_r, wall_drywall_thick_in, wall_concrete_thick_in, wall_height_above_grade)

    # Create Kiva foundation
    foundation = apply_kiva_walled_foundation(model, ext_rigid_r, int_rigid_r, ext_rigid_ins_offset,
                                              int_rigid_ins_offset, ext_rigid_ins_height,
                                              int_rigid_ins_height, wall_height_above_grade,
                                              wall_concrete_thick_in, wall_drywall_thick_in)

    # Define materials
    mat_concrete = Material.Concrete(wall_concrete_thick_in)

    # Define construction
    constr = Construction.new(wall_constr_name, [1])
    constr.add_layer(mat_concrete)
    if wall_drywall_thick_in > 0
      constr.add_layer(Material.GypsumWall(wall_drywall_thick_in))
    end

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, wall_surfaces, model)

    # Assign surfaces to Kiva foundation
    wall_surfaces.each do |wall_surface|
      wall_surface.setAdjacentFoundation(foundation)
    end
  end

  def self.apply_foundation_slab(runner, model, surface, constr_name,
                                 under_r, under_width, gap_r,
                                 perimeter_r, perimeter_depth,
                                 whole_r, concrete_thick_in, exposed_perimeter,
                                 mat_carpet, foundation)

    return if surface.nil?

    if foundation.nil?
      # Create Kiva foundation for slab
      thick = UnitConversions.convert(concrete_thick_in, 'in', 'ft')
      foundation = create_kiva_slab_foundation(model, under_r, under_width,
                                               gap_r, thick, perimeter_r, perimeter_depth,
                                               concrete_thick_in)
    else
      # Kiva foundation (for crawlspace/basement) exists
      if (under_r > 0) && (under_width > 0)
        int_horiz_mat = create_insulation_material(model, 'FoundationIntHorizIns', under_r)
        foundation.setInteriorHorizontalInsulationMaterial(int_horiz_mat)
        foundation.setInteriorHorizontalInsulationDepth(0)
        foundation.setInteriorHorizontalInsulationWidth(UnitConversions.convert(under_width, 'ft', 'm'))
      end
    end

    # Define materials
    mat_concrete = nil
    mat_soil = nil
    if concrete_thick_in > 0
      mat_concrete = Material.Concrete(concrete_thick_in)
    else
      # Use 0.5 - 1.0 inches of soil, per Neal Kruis recommendation
      mat_soil = Material.Soil(0.5)
    end
    mat_rigid = nil
    if whole_r > 0
      rigid_thick_in = whole_r * BaseMaterial.InsulationRigid.k_in
      mat_rigid = Material.new(name = 'SlabRigidIns', thick_in = rigid_thick_in, mat_base = BaseMaterial.InsulationRigid, k_in = rigid_thick_in / whole_r)
    end

    # Define construction
    constr = Construction.new(constr_name, [1.0])
    if not mat_rigid.nil?
      constr.add_layer(mat_rigid)
    end
    if not mat_concrete.nil?
      constr.add_layer(mat_concrete)
    end
    if not mat_soil.nil?
      constr.add_layer(mat_soil)
    end
    if not mat_carpet.nil?
      constr.add_layer(mat_carpet)
    end

    # Create and assign construction to surfaces
    constr.create_and_assign_constructions(runner, [surface], model)

    # Assign surface to Kiva foundation
    surface.setAdjacentFoundation(foundation)
    surface.createSurfacePropertyExposedFoundationPerimeter('TotalExposedPerimeter', UnitConversions.convert(exposed_perimeter, 'ft', 'm'))
  end

  def self.apply_door(runner, model, subsurfaces, constr_name, ufactor, inside_film, outside_film)
    return if subsurfaces.empty?

    # Define materials
    door_Rvalue = 1.0 / ufactor - inside_film.rvalue - outside_film.rvalue
    door_thickness = 1.75 # in
    fin_door_mat = Material.new(name = 'DoorMaterial', thick_in = door_thickness, mat_base = BaseMaterial.Wood, k_in = 1.0 / door_Rvalue * door_thickness)

    # Set paths
    path_fracs = [1]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(fin_door_mat)

    # Create and assign construction to subsurfaces
    constr.create_and_assign_constructions(runner, subsurfaces, model)
  end

  def self.apply_window(runner, model, subsurface, constr_name, weather,
                        heat_sch, cool_sch, ufactor, shgc, heat_shade_mult, cool_shade_mult)

    apply_window_skylight(runner, model, 'Window', subsurface, constr_name, weather,
                          heat_sch, cool_sch, ufactor, shgc, heat_shade_mult, cool_shade_mult)
  end

  def self.apply_skylight(runner, model, subsurface, constr_name, weather,
                          heat_sch, cool_sch, ufactor, shgc, heat_shade_mult, cool_shade_mult)

    apply_window_skylight(runner, model, 'Skylight', subsurface, constr_name, weather,
                          heat_sch, cool_sch, ufactor, shgc, heat_shade_mult, cool_shade_mult)
  end

  def self.apply_partition_walls(runner, model, constr_name, drywall_thick_in, frac_of_ffa,
                                 basement_frac_of_cfa, cond_base_surfaces, living_space)

    imdefs = []

    # Determine additional partition wall mass required
    addtl_surface_area_base = frac_of_ffa * living_space.floorArea * basement_frac_of_cfa
    addtl_surface_area_lv = frac_of_ffa * living_space.floorArea * (1.0 - basement_frac_of_cfa)

    if addtl_surface_area_lv > 0
      # Add remaining partition walls within spaces (those without geometric representation)
      # as internal mass object.
      obj_name = "#{living_space.name} Living Partition"
      imdef = create_os_int_mass_and_def(model, obj_name, living_space, addtl_surface_area_lv)
      imdefs << imdef
    end

    if addtl_surface_area_base > 0
      # Add remaining partition walls within spaces (those without geometric representation)
      # as internal mass object.
      obj_name = "#{living_space.name} Basement Partition"
      imdef = create_os_int_mass_and_def(model, obj_name, living_space, addtl_surface_area_base)
      cond_base_surfaces << imdef
      imdefs << imdef
    end

    apply_wood_stud_wall(runner, model, imdefs, nil, constr_name,
                         0, 1, 3.5, false, 0.16,
                         drywall_thick_in, 0, 0, nil, drywall_thick_in,
                         Material.AirFilmVertical,
                         Material.AirFilmVertical)
  end

  def self.apply_furniture(runner, model, mass_lb_per_sqft, density_lb_per_cuft,
                           mat, basement_frac_of_cfa, cond_base_surfaces, living_space)

    # Add user-specified furniture mass
    model.getSpaces.each do |space|
      furnAreaFraction = nil # Fraction of conditioned floor area
      furnConductivity = mat.k_in
      furnSolarAbsorptance = 0.6
      furnSpecHeat = mat.cp
      furnDensity = density_lb_per_cuft
      if (space == living_space) || Geometry.is_unconditioned_basement(space)
        furnAreaFraction = 1.0
        furnMass = mass_lb_per_sqft
      elsif Geometry.is_garage(space)
        furnAreaFraction = 0.1
        furnMass = 2.0
      end

      next if furnAreaFraction.nil?
      next if furnAreaFraction <= 0
      next if space.floorArea <= 0

      mat_obj_name_space = "#{Constants.ObjectNameFurniture} material #{space.name}"
      constr_obj_name_space = "#{Constants.ObjectNameFurniture} construction #{space.name}"
      mass_obj_name_space = "#{Constants.ObjectNameFurniture} mass #{space.name}"

      furnThickness = UnitConversions.convert(furnMass / (furnDensity * furnAreaFraction), 'ft', 'in')

      # Define materials
      mat_fm = Material.new(name = mat_obj_name_space, thick_in = furnThickness, mat_base = nil, k_in = furnConductivity, rho = furnDensity, cp = furnSpecHeat, tAbs = 0.9, sAbs = furnSolarAbsorptance, vAbs = 0.1)

      # Set paths
      path_fracs = [1]

      # Define construction
      constr = Construction.new(constr_obj_name_space, path_fracs)
      constr.add_layer(mat_fm)

      imdefs = []
      if space == living_space
        # if living space, judge if includes conditioned basement, create furniture independently
        living_surface_area = furnAreaFraction * space.floorArea * (1 - basement_frac_of_cfa)
        base_surface_area = furnAreaFraction * space.floorArea * basement_frac_of_cfa
        # living furniture mass
        if living_surface_area > 0
          living_obj_name = mass_obj_name_space + ' living'
          imdef = create_os_int_mass_and_def(model, living_obj_name, space, living_surface_area)
          imdefs << imdef
        end
        # basement furniture mass
        if base_surface_area > 0
          base_obj_name = mass_obj_name_space + ' basement'
          imdef = create_os_int_mass_and_def(model, base_obj_name, space, base_surface_area)
          cond_base_surfaces << imdef
          imdefs << imdef
        end
      else
        surface_area = furnAreaFraction * space.floorArea
        imdef = create_os_int_mass_and_def(model, mass_obj_name_space, space, surface_area)
        imdefs << imdef
      end
      # Create and assign construction to surfaces
      constr.create_and_assign_constructions(runner, imdefs, model)
    end
  end

  def self.create_os_int_mass_and_def(model, object_name, space, area)
    # EnergyPlus documentation: If both sides of the surface exchange energy with the zone
    # then the user should input twice the area when defining the Internal Mass object.
    imdef = OpenStudio::Model::InternalMassDefinition.new(model)
    imdef.setName(object_name)
    imdef.setSurfaceArea(area)

    im = OpenStudio::Model::InternalMass.new(imdef)
    im.setName(object_name)
    im.setSpace(space)

    return imdef
  end

  def self.get_default_interior_shading_factors()
    summer = 0.70
    winter = 0.85
    return summer, winter
  end

  def self.get_default_roof_color(roof_type, solar_absorptance)
    map = get_roof_color_and_solar_absorptance_map
    color_map = {}
    map.each do |key, value|
      next unless key[1] == roof_type

      color_map[key[0]] = value
    end
    color = color_map.min_by { |k, v| (v - solar_absorptance).abs }[0]
    return color
  end

  def self.get_default_roof_solar_absorptance(roof_type, color)
    map = get_roof_color_and_solar_absorptance_map
    return map[[color, roof_type]]
  end

  def self.get_default_wall_color(solar_absorptance)
    map = get_wall_color_and_solar_absorptance_map
    color = map.min_by { |k, v| (v - solar_absorptance).abs }[0]
    return color
  end

  def self.get_default_wall_solar_absorptance(color)
    map = get_wall_color_and_solar_absorptance_map
    return map[color]
  end

  private

  def self.get_roof_color_and_solar_absorptance_map
    return { [HPXML::ColorDark, HPXML::RoofTypeAsphaltShingles] => 0.92,
             [HPXML::ColorMediumDark, HPXML::RoofTypeAsphaltShingles] => 0.89,
             [HPXML::ColorMedium, HPXML::RoofTypeAsphaltShingles] => 0.85,
             [HPXML::ColorLight, HPXML::RoofTypeAsphaltShingles] => 0.75,
             [HPXML::ColorReflective, HPXML::RoofTypeAsphaltShingles] => 0.50,
             [HPXML::ColorDark, HPXML::RoofTypeWoodShingles] => 0.92,
             [HPXML::ColorMediumDark, HPXML::RoofTypeWoodShingles] => 0.89,
             [HPXML::ColorMedium, HPXML::RoofTypeWoodShingles] => 0.85,
             [HPXML::ColorLight, HPXML::RoofTypeWoodShingles] => 0.75,
             [HPXML::ColorReflective, HPXML::RoofTypeWoodShingles] => 0.50,
             [HPXML::ColorDark, HPXML::RoofTypeClayTile] => 0.90,
             [HPXML::ColorMediumDark, HPXML::RoofTypeClayTile] => 0.83,
             [HPXML::ColorMedium, HPXML::RoofTypeClayTile] => 0.75,
             [HPXML::ColorLight, HPXML::RoofTypeClayTile] => 0.60,
             [HPXML::ColorReflective, HPXML::RoofTypeClayTile] => 0.30,
             [HPXML::ColorDark, HPXML::RoofTypeMetal] => 0.90,
             [HPXML::ColorMediumDark, HPXML::RoofTypeMetal] => 0.83,
             [HPXML::ColorMedium, HPXML::RoofTypeMetal] => 0.75,
             [HPXML::ColorLight, HPXML::RoofTypeMetal] => 0.60,
             [HPXML::ColorReflective, HPXML::RoofTypeMetal] => 0.30 }
  end

  def self.get_wall_color_and_solar_absorptance_map
    return { HPXML::ColorDark => 0.95,
             HPXML::ColorMediumDark => 0.85,
             HPXML::ColorMedium => 0.70,
             HPXML::ColorLight => 0.50,
             HPXML::ColorReflective => 0.30 }
  end

  def self.get_gap_factor(install_grade, framing_factor, cavity_r)
    if cavity_r <= 0
      return 0 # Gap factor only applies when there is cavity insulation
    elsif install_grade == 1
      return 0
    elsif install_grade == 2
      return 0.02 * (1 - framing_factor)
    elsif install_grade == 3
      return 0.05 * (1 - framing_factor)
    end

    return 0
  end

  def self.create_kiva_slab_foundation(model, int_horiz_r, int_horiz_width, int_vert_r,
                                       int_vert_depth, ext_vert_r, ext_vert_depth,
                                       concrete_thick_in)

    # Create the Foundation:Kiva object for slab foundations
    foundation = OpenStudio::Model::FoundationKiva.new(model)

    # Interior horizontal insulation
    if (int_horiz_r > 0) && (int_horiz_width > 0)
      int_horiz_mat = create_insulation_material(model, 'FoundationIntHorizIns', int_horiz_r)
      foundation.setInteriorHorizontalInsulationMaterial(int_horiz_mat)
      foundation.setInteriorHorizontalInsulationDepth(0)
      foundation.setInteriorHorizontalInsulationWidth(UnitConversions.convert(int_horiz_width, 'ft', 'm'))
    end

    # Interior vertical insulation
    if int_vert_r > 0
      int_vert_mat = create_insulation_material(model, 'FoundationIntVertIns', int_vert_r)
      foundation.setInteriorVerticalInsulationMaterial(int_vert_mat)
      foundation.setInteriorVerticalInsulationDepth(UnitConversions.convert(int_vert_depth, 'ft', 'm'))
    end

    # Exterior vertical insulation
    if (ext_vert_r > 0) && (ext_vert_depth > 0)
      ext_vert_mat = create_insulation_material(model, 'FoundationExtVertIns', ext_vert_r)
      foundation.setExteriorVerticalInsulationMaterial(ext_vert_mat)
      foundation.setExteriorVerticalInsulationDepth(UnitConversions.convert(ext_vert_depth, 'ft', 'm'))
    end

    foundation.setWallHeightAboveGrade(UnitConversions.convert(concrete_thick_in, 'in', 'm'))
    foundation.setWallDepthBelowSlab(UnitConversions.convert(8.0, 'in', 'm'))

    apply_kiva_settings(model)

    return foundation
  end

  def self.apply_kiva_walled_foundation(model, ext_vert_r, int_vert_r,
                                        ext_vert_offset, int_vert_offset, ext_vert_depth, int_vert_depth,
                                        wall_height_above_grade, wall_concrete_thick_in, wall_drywall_thick_in)

    # Create the Foundation:Kiva object for crawl/basement foundations
    foundation = OpenStudio::Model::FoundationKiva.new(model)

    # Interior vertical insulation
    if (int_vert_r > 0) && (int_vert_depth > 0)
      int_vert_mat = create_insulation_material(model, 'FoundationIntVertIns', int_vert_r)
      foundation.addCustomBlock(int_vert_mat,
                                UnitConversions.convert(int_vert_depth, 'ft', 'm'),
                                -int_vert_mat.thickness,
                                UnitConversions.convert(int_vert_offset, 'ft', 'm'))
    end

    # Exterior vertical insulation
    if (ext_vert_r > 0) && (ext_vert_depth > 0)
      ext_vert_mat = create_insulation_material(model, 'FoundationExtVertIns', ext_vert_r)
      foundation.addCustomBlock(ext_vert_mat,
                                UnitConversions.convert(ext_vert_depth, 'ft', 'm'),
                                UnitConversions.convert(wall_concrete_thick_in + wall_drywall_thick_in, 'in', 'm'),
                                UnitConversions.convert(ext_vert_offset, 'ft', 'm'))
    end

    foundation.setWallHeightAboveGrade(UnitConversions.convert(wall_height_above_grade, 'ft', 'm'))
    foundation.setWallDepthBelowSlab(UnitConversions.convert(8.0, 'in', 'm'))

    apply_kiva_settings(model)

    return foundation
  end

  def self.apply_kiva_settings(model)
    # Set the Foundation:Kiva:Settings object
    soil_mat = BaseMaterial.Soil
    settings = model.getFoundationKivaSettings
    settings.setSoilConductivity(UnitConversions.convert(soil_mat.k_in, 'Btu*in/(hr*ft^2*R)', 'W/(m*K)'))
    settings.setSoilDensity(UnitConversions.convert(soil_mat.rho, 'lbm/ft^3', 'kg/m^3'))
    settings.setSoilSpecificHeat(UnitConversions.convert(soil_mat.cp, 'Btu/(lbm*R)', 'J/(kg*K)'))
    settings.setGroundSolarAbsorptivity(0.9)
    settings.setGroundThermalAbsorptivity(0.9)
    settings.setGroundSurfaceRoughness(0.03)
    settings.setFarFieldWidth(40) # TODO: Set based on neighbor distances?
    settings.setDeepGroundBoundaryCondition('ZeroFlux')
    settings.setDeepGroundDepth(40)
    settings.setMinimumCellDimension(0.2)
    settings.setMaximumCellGrowthCoefficient(3.0)
    settings.setSimulationTimestep('Hourly')
  end

  def self.create_insulation_material(model, name, rvalue)
    rigid_mat = BaseMaterial.InsulationRigid
    mat = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    mat.setName(name)
    mat.setRoughness('Rough')
    mat.setThickness(UnitConversions.convert(rvalue * rigid_mat.k_in, 'in', 'm'))
    mat.setConductivity(UnitConversions.convert(rigid_mat.k_in, 'Btu*in/(hr*ft^2*R)', 'W/(m*K)'))
    mat.setDensity(UnitConversions.convert(rigid_mat.rho, 'lbm/ft^3', 'kg/m^3'))
    mat.setSpecificHeat(UnitConversions.convert(rigid_mat.cp, 'Btu/(lbm*R)', 'J/(kg*K)'))
    return mat
  end

  def self.create_footing_material(model, name)
    footing_mat = Material.Concrete(8.0)
    mat = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    mat.setName(name)
    mat.setRoughness('Rough')
    mat.setThickness(UnitConversions.convert(footing_mat.thick_in, 'in', 'm'))
    mat.setConductivity(UnitConversions.convert(footing_mat.k_in, 'Btu*in/(hr*ft^2*R)', 'W/(m*K)'))
    mat.setDensity(UnitConversions.convert(footing_mat.rho, 'lbm/ft^3', 'kg/m^3'))
    mat.setSpecificHeat(UnitConversions.convert(footing_mat.cp, 'Btu/(lbm*R)', 'J/(kg*K)'))
    mat.setThermalAbsorptance(footing_mat.tAbs)
    return mat
  end

  def self.apply_window_skylight(runner, model, type, subsurface, constr_name, weather,
                                 heat_sch, cool_sch, ufactor, shgc, heat_shade_mult, cool_shade_mult)

    # Define shade and schedule
    { 'Cooling' => [cool_sch, cool_shade_mult],
      'Heating' => [heat_sch, heat_shade_mult] }.each do |mode, values|
      sch, shade_mult = values
      next if shade_mult >= 1.0

      shade_name = "#{type}#{mode}Shade"
      sc_name = "#{type}#{mode}ShadingControl"

      # Reuse existing Shade?
      # Note: We still create a unique ShadingControl per subsurface in order to
      # prevent the shading control from being used by subsurfaces in different
      # zones, which is probably not a good idea.
      sm = nil
      model.getShades.each do |shade|
        next unless (shade.solarTransmittance - shade_mult).abs < 0.0001
        next unless shade.name.to_s.start_with? shade_name

        sm = shade
        break
      end

      if sm.nil?
        shade_abs = 0.00001
        shade_ref = 1.0 - shade_mult - shade_abs

        # Shade
        sm = OpenStudio::Model::Shade.new(model)
        sm.setName(shade_name)
        sm.setSolarTransmittance(shade_mult)
        sm.setSolarReflectance(shade_ref)
        sm.setVisibleTransmittance(shade_mult)
        sm.setVisibleReflectance(shade_ref)
        sm.setThermalHemisphericalEmissivity(shade_abs)
        sm.setThermalTransmittance(shade_mult)
        sm.setThickness(0.0001)
        sm.setConductivity(10000)
        sm.setShadetoGlassDistance(0.001)
        sm.setTopOpeningMultiplier(0)
        sm.setBottomOpeningMultiplier(0)
        sm.setLeftSideOpeningMultiplier(0)
        sm.setRightSideOpeningMultiplier(0)
        sm.setAirflowPermeability(0)
      end

      # ShadingControl
      sc = OpenStudio::Model::ShadingControl.new(sm)
      sc.setName(sc_name)
      sc.setShadingType('InteriorShade')
      sc.setShadingControlType('OnIfScheduleAllows')
      sc.setSchedule(sch.schedule)
      subsurface.addShadingControl(sc)
    end

    # Define materials
    if type == 'Skylight'
      # As of 2004, NFRC skylights are rated at a 20-degree slope (instead of vertical), but
      # the E+ SimpleGlazingSystem model accepts a U-factor that "is assumed to be for
      # vertically mounted products". According to NFRC, "Ratings ... shall be converted to
      # the 20-deg slope from the vertical position by multiplying the tested value at vertical
      # by 1.20." Thus we divide by 1.2 to get the vertical position value.
      ufactor /= 1.2
    end
    glaz_mat = GlazingMaterial.new("#{type}Material", ufactor, shgc)

    # Set paths
    path_fracs = [1]

    # Define construction
    constr = Construction.new(constr_name, path_fracs)
    constr.add_layer(glaz_mat)

    # Create and assign construction to subsurfaces
    constr.create_and_assign_constructions(runner, [subsurface], model)
  end
end

class Construction
  # Facilitates creating and assigning an OpenStudio construction (with accompanying
  # OpenStudio Materials) from Material objects. Handles parallel path calculations.

  def initialize(name, path_widths)
    @name = name
    @path_widths = path_widths
    @path_fracs = []
    @sum_path_fracs = @path_widths.sum(0.0)
    path_widths.each do |path_width|
      @path_fracs << path_width / path_widths.sum(0.0)
    end
    @layers_names = []
    @layers_materials = []
  end

  def add_layer(materials, name = nil)
    # materials: Either a Material object or a list of Material objects
    # include_in_construction: false if the layer that should not be included in the
    #                          resulting construction but is used to calculate the
    #                          effective R-value.
    # name: Name of the layer; required if multiple materials are provided. Otherwise the
    #       Material.name will be used.
    if not materials.kind_of?(Array)
      @layers_materials << [materials]
      if not name.nil?
        @layers_names << name
      else
        @layers_names << materials.name
      end
    else
      @layers_materials << materials
      if not name.nil?
        @layers_names << name
      else
        @layers_names << 'ParallelMaterial'
      end
    end
  end

  def assembly_rvalue()
    # Calculate overall R-value for assembly
    validate

    u_overall = 0
    @path_fracs.each_with_index do |path_frac, path_num|
      # For each parallel path, sum series:
      r_path = 0
      @layers_materials.each do |layer_materials|
        if layer_materials.size == 1
          # One material for this layer
          r_path += layer_materials[0].rvalue
        else
          # Multiple parallel materials for this layer, use appropriate one
          r_path += layer_materials[path_num].rvalue
        end
      end
      u_overall += 1.0 / r_path * path_frac
    end
    r_overall = 1.0 / u_overall
    return r_overall
  end

  # Creates constructions as needed and assigns to surfaces.
  # Leave name as nil if the materials (e.g., exterior finish) apply to multiple constructions.
  def create_and_assign_constructions(runner, surfaces, model)
    validate

    # Create list of OpenStudio materials
    materials = construct_materials(runner, model)

    # Create OpenStudio construction and assign to surface
    constr = OpenStudio::Model::Construction.new(model)
    constr.setName(@name)
    constr.setLayers(materials)
    revconstr = nil

    # Assign constructions to surfaces
    surfaces.each do |surface|
      surface.setConstruction(constr)

      # Assign reverse construction to adjacent surface as needed
      next if surface.is_a?(OpenStudio::Model::SubSurface) || surface.is_a?(OpenStudio::Model::InternalMassDefinition) || (not surface.adjacentSurface.is_initialized)

      if revconstr.nil?
        revconstr = constr.reverseConstruction
      end
      adjacent_surface = surface.adjacentSurface.get
      adjacent_surface.setConstruction(revconstr)
    end
  end

  private

  def get_parallel_material(curr_layer_num, name)
    # Returns a Material object with effective properties for the specified
    # parallel path layer of the construction.

    mat = Material.new(name)

    curr_layer_materials = @layers_materials[curr_layer_num]

    r_overall = assembly_rvalue()

    # Calculate individual R-values for each layer
    sum_r_all_layers = 0
    sum_r_parallel_layers = 0
    layer_rvalues = []
    @layers_materials.each do |layer_materials|
      u_path = 0
      layer_materials.each_with_index do |layer_material, idx|
        if layer_materials.size > 1
          u_path += @path_fracs[idx] / (layer_material.thick / layer_material.k)
        else
          u_path += 1.0 / (layer_material.thick / layer_material.k)
        end
      end
      r_path = 1.0 / u_path
      layer_rvalues << r_path
      sum_r_all_layers += r_path
      if layer_materials.size > 1
        sum_r_parallel_layers += r_path
      end
    end

    # Material R-value
    # Apportion R-value to the current parallel path layer
    mat.rvalue = layer_rvalues[curr_layer_num] + (r_overall - sum_r_all_layers) * layer_rvalues[curr_layer_num] / sum_r_parallel_layers

    # Material thickness and conductivity
    mat.thick_in = curr_layer_materials[0].thick_in # All paths have equal thickness
    mat.thick = curr_layer_materials[0].thick # All paths have equal thickness
    mat.k = mat.thick / mat.rvalue

    # Material density
    mat.rho = 0
    @path_fracs.each_with_index do |path_frac, path_num|
      mat.rho += curr_layer_materials[path_num].rho * path_frac
    end

    # Material specific heat
    mat.cp = 0
    @path_fracs.each_with_index do |path_frac, path_num|
      mat.cp += (curr_layer_materials[path_num].cp * curr_layer_materials[path_num].rho * path_frac) / mat.rho
    end

    return mat
  end

  def construct_materials(runner, model)
    # Create materials
    materials = []
    @layers_materials.each_with_index do |layer_materials, layer_num|
      if layer_materials.size == 1
        next if layer_materials[0].name == Constants.AirFilm # Do not include air films in construction

        mat = Construction.create_os_material(runner, model, layer_materials[0])
      else
        parallel_path_mat = get_parallel_material(layer_num, @layers_names[layer_num])
        mat = Construction.create_os_material(runner, model, parallel_path_mat)
      end
      materials << mat
    end
    return materials
  end

  def validate
    # Check that sum of path fracs equal 1
    if (@sum_path_fracs <= 0.999) || (@sum_path_fracs >= 1.001)
      fail "Invalid construction: Sum of path fractions (#{@sum_path_fracs}) is not 1."
    end

    # Check that all path fractions are not negative
    @path_fracs.each do |path_frac|
      if path_frac < 0
        fail "Invalid construction: Path fraction (#{path_frac}) must be greater than or equal to 0."
      end
    end

    # Check if all materials are GlazingMaterial
    all_glazing = true
    @layers_materials.each do |layer_materials|
      layer_materials.each do |mat|
        if not mat.is_a? GlazingMaterial
          all_glazing = false
        end
      end
    end
    if all_glazing
      # Check that no parallel materials
      @layers_materials.each do |layer_materials|
        if layer_materials.size > 1
          fail 'Invalid construction: Cannot have multiple GlazingMaterials in a single layer.'
        end
      end
      return
    end

    # Check for valid object types
    @layers_materials.each do |layer_materials|
      layer_materials.each do |mat|
        if (not mat.is_a? SimpleMaterial) && (not mat.is_a? Material)
          fail 'Invalid construction: Materials must be instances of SimpleMaterial or Material classes.'
        end
      end
    end

    # Check if invalid number of materials in a layer
    @layers_materials.each do |layer_materials|
      if (layer_materials.size > 1) && (layer_materials.size < @path_fracs.size)
        fail 'Invalid construction: Layer must either have one material or same number of materials as paths.'
      end
    end

    # Check if multiple materials in a given layer have differing thicknesses
    @layers_materials.each do |layer_materials|
      next unless layer_materials.size > 1

      thick_in = nil
      layer_materials.each do |mat|
        if thick_in.nil?
          thick_in = mat.thick_in
        elsif thick_in != mat.thick_in
          fail 'Invalid construction: Materials in a layer have different thicknesses.'
        end
      end
    end

    # Check if multiple non-contiguous parallel layers
    found_parallel = false
    last_parallel = false
    @layers_materials.each do |layer_materials|
      if layer_materials.size > 1
        if not found_parallel
          found_parallel = true
        elsif not last_parallel
          fail 'Invalid construction: Non-contiguous parallel layers found.'
        end
      end
      last_parallel = (layer_materials.size > 1)
    end
  end

  # Creates (or returns an existing) OpenStudio Material from our own Material object
  def self.create_os_material(runner, model, material)
    name = material.name
    tolerance = 0.0001
    if material.is_a? SimpleMaterial
      # Material already exists?
      model.getMasslessOpaqueMaterials.each do |mat|
        next if mat.roughness.downcase.to_s != 'rough'
        next if (mat.thermalResistance - UnitConversions.convert(material.rvalue, 'hr*ft^2*F/Btu', 'm^2*K/W')).abs > tolerance

        return mat
      end
      # New material
      mat = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
      mat.setName(name)
      mat.setRoughness('Rough')
      mat.setThermalResistance(UnitConversions.convert(material.rvalue, 'hr*ft^2*F/Btu', 'm^2*K/W'))
    elsif material.is_a? GlazingMaterial
      max_ufactor = UnitConversions.convert(7.0, 'W/(m^2*K)', 'Btu/(hr*ft^2*F)') # Max value EnergyPlus allows
      if material.ufactor > max_ufactor
        runner.registerWarning("Glazing U-factor (#{material.ufactor}) for '#{material.name}' above maximum expected value. U-factor decreased to #{max_ufactor.round(2)}.")
        material.ufactor = max_ufactor.round(2)
      end

      # Material already exists?
      model.getSimpleGlazings.each do |mat|
        next if (mat.uFactor - UnitConversions.convert(material.ufactor, 'Btu/(hr*ft^2*F)', 'W/(m^2*K)')).abs > tolerance
        next if (mat.solarHeatGainCoefficient - material.shgc).abs > tolerance

        return mat
      end
      # New material
      mat = OpenStudio::Model::SimpleGlazing.new(model)
      mat.setName(name)
      mat.setUFactor(UnitConversions.convert(material.ufactor, 'Btu/(hr*ft^2*F)', 'W/(m^2*K)'))
      mat.setSolarHeatGainCoefficient(material.shgc)
    else
      # Material already exists?
      model.getStandardOpaqueMaterials.each do |mat|
        next if mat.roughness.downcase.to_s != 'rough'
        next if (mat.thickness - UnitConversions.convert(material.thick_in, 'in', 'm')).abs > tolerance
        next if (mat.conductivity - UnitConversions.convert(material.k, 'Btu/(hr*ft*R)', 'W/(m*K)')).abs > tolerance
        next if (mat.density - UnitConversions.convert(material.rho, 'lbm/ft^3', 'kg/m^3')).abs > tolerance
        next if (mat.specificHeat - UnitConversions.convert(material.cp, 'Btu/(lbm*R)', 'J/(kg*K)')).abs > tolerance
        next if (not material.tAbs.nil?) && ((mat.thermalAbsorptance - material.tAbs).abs > tolerance)
        next if (not material.sAbs.nil?) && ((mat.solarAbsorptance - material.sAbs).abs > tolerance)
        next if (not material.vAbs.nil?) && ((mat.visibleAbsorptance - material.vAbs).abs > tolerance)

        return mat
      end
      # New material
      mat = OpenStudio::Model::StandardOpaqueMaterial.new(model)
      mat.setName(name)
      mat.setRoughness('Rough')
      mat.setThickness(UnitConversions.convert(material.thick_in, 'in', 'm'))
      mat.setConductivity(UnitConversions.convert(material.k, 'Btu/(hr*ft*R)', 'W/(m*K)'))
      mat.setDensity(UnitConversions.convert(material.rho, 'lbm/ft^3', 'kg/m^3'))
      mat.setSpecificHeat(UnitConversions.convert(material.cp, 'Btu/(lbm*R)', 'J/(kg*K)'))
      if not material.tAbs.nil?
        mat.setThermalAbsorptance(material.tAbs)
      end
      if not material.sAbs.nil?
        mat.setSolarAbsorptance(material.sAbs)
      end
      if not material.vAbs.nil?
        mat.setVisibleAbsorptance(material.vAbs)
      end
    end
    return mat
  end
end
