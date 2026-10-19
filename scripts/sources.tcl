set root [file dirname [file dirname [file normalize [info script]]]]
set sources [list]
foreach f {T80_Pack.vhd T80_MCode.vhd T80_ALU.vhd T80_Reg.vhd T80.vhd T80s.vhd} {
  lappend sources [file join $root rtl cpu $f]
}
foreach f {vdp18_pack-p.vhd vdp18_col_pack-p.vhd vdp18_clk_gen.vhd vdp18_hor_vert.vhd vdp18_ctrl.vhd vdp18_cpuio.vhd vdp18_addr_mux.vhd vdp18_pattern.vhd vdp18_sprite.vhd vdp18_col_mux.vhd vdp18_core.vhd} {
  lappend sources [file join $root rtl vdp18 $f]
}
foreach f {storage/vfat_name_pkg.vhd storage/vfat_lfn_decoder.vhd storage/bit90_sd_file_pkg.vhd storage/bit90_sd_spi_fat32.vhd storage/bit90_sd_browser.vhd storage/bit90_sd_slot_mux.vhd storage/bit90_cart_loader.vhd storage/bit90_tape_player.vhd storage/bit90_bas_loader.vhd audio/sn76489_audio.vhd audio/bit90_sn76489.vhd audio/pcm_to_pdm.vhd audio/ak4432_audio.vhd bit90_vdp.vhd bit90_rom_v31.vhd bit90_xbas_rom.vhd bit90_controller.vhd bit90_system.vhd bit90_keyboard.vhd bit90_config.vhd bit90_font_pkg.vhd bit90_demo_image.vhd bit90_test_patterns.vhd bit90_vdp_demo.vhd video/tyto_types_pkg.vhd video/DVI_Constants.vhd video/TMDS_Encoder.vhd video/hdmi_tx_selectio.vhd video/audio_pcm_cdc.vhd video/hdmi_packet_assembler.vhd video/audio_sample_packet.vhd video/audio_infoframe.vhd video/audio_clock_regeneration.vhd video/avi_infoframe.vhd video/terc4_encoder.vhd video/hdmi_proven_tx.vhd video/bit90_framebuffer.vhd video/bit90_video_clock.vhd bit90_m1_r6.vhd bit90_m2_r6.vhd mega65_r3_max10.vhd bit90_m2_r3.vhd} {
  lappend sources [file join $root rtl $f]
}
