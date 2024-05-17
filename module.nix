{ dtbName }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixos-x13s;

  x13sPackages = import ./packages/default.nix { inherit lib pkgs; };

  linuxPackages_x13s =
    if cfg.kernel == "mainline" then
      pkgs.linuxPackages_latest
    else
      pkgs.linuxPackagesFor (
        if cfg.kernel == "jhovold" then x13sPackages.linux_jhovold else throw "Unsupported kernel"
      );
  dtb = "${linuxPackages_x13s.kernel}/dtbs/qcom/${dtbName}";
  dtbEfiPath = "dtbs/x13s.dtb";
in
{
  options.nixos-x13s = {
    enable = lib.mkEnableOption "x13s hardware support";

    bluetoothMac = lib.mkOption {
      type = lib.types.str;
      description = "Bluetooth MAC address to set on boot";
    };

    kernel = lib.mkOption {
      type = lib.types.enum [
        "jhovold"
        "mainline"
      ];
      description = "Which patched kernel to use. jhovold is the latest RC or release with some x13s specific patches, and mainline is nixos latest";
      default = "jhovold";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.efibootmgr ];

    hardware.enableAllFirmware = true;
    hardware.firmware = [ x13sPackages."x13s/extra-firmware" ];

    systemd.services.pd-mapper = {
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${lib.getExe x13sPackages.pd-mapper}";
        Restart = "always";
      };
    };

    boot = {
      loader.efi.canTouchEfiVariables = true;
      loader.systemd-boot.enable = lib.mkDefault true;
      loader.systemd-boot.extraFiles = {
        "${dtbEfiPath}" = dtb;
      };

      kernelPackages = linuxPackages_x13s;

      kernelParams = [
        # needed to boot
        "dtb=${dtbEfiPath}"

        # jhovold recommended
        "efi=noruntime"
        "clk_ignore_unused"
        "pd_ignore_unused"
        "regulator_ignore_unused"
        "arm64.nopauth"

        # blacklist graphics in initrd so the firmware can load from disk
        "rd.driver.blacklist=msm"
      ];

      initrd = {
        kernelModules = [
          "nvme"
          "phy-qcom-qmp-pcie"
          "pcie-qcom"

          "i2c-core"
          "i2c-hid"
          "i2c-hid-of"
          "i2c-qcom-geni"

          "leds_qcom_lpg"
          "pwm_bl"
          "qrtr"
          "pmic_glink_altmode"
          "gpio_sbu_mux"
          "phy-qcom-qmp-combo"
          "gpucc_sc8280xp"
          "dispcc_sc8280xp"
          "phy_qcom_edp"
          "panel-edp"
          # "msm"
        ];
      };
    };

    nixpkgs.overlays = [
      (_: super: {
        # don't try and use zfs
        zfs = super.zfs.overrideAttrs (_: {
          meta.platforms = [ ];
        });

        # allow missing modules
        makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });
      })
    ];

    # default is performance
    powerManagement.cpuFreqGovernor = "ondemand";

    systemd.services.bluetooth-x13s-mac = {
      wantedBy = [ "multi-user.target" ];
      before = [ "bluetooth.service" ];
      requiredBy = [ "bluetooth.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.util-linux}/bin/script -q -c '${pkgs.bluez}/bin/btmgmt --index 0 public-addr ${cfg.bluetoothMac}'";
      };
    };
  };
}
