# kernel/common patches

What this dir carries and why, one entry per patch. How each patch works is in its header.

## Base

Each SoC's kernel, after the SoC's own stack

Applied in number order on the stock kernel that `kernel/<soc>/kernel.conf` pins. A SoC leaves
a patch out by naming it in its optional `common-skip` file.

Last rebased: 2026-10-29 (iris gen1 HEVC Remote Play).

## Carried

### UFS storage

- **1001** The UFS controller's interrupt no longer stays masked for good after a failed host reset.
  Source: jaewun (thor-suspend-fixes).
- **1007** A UFS link that fails to wake after a clock change reports the failure, so the clock
  change is rolled back instead of kept. Applies: every SoC (the RP5 boots from UFS too).
  Source: jaewun set.
- **1008** The UFS link no longer gets marked broken when hardware auto-hibern8 and clock gating
  both park it on idle. Applies: every SoC. Source: jaewun set.
- **1010** The UFS M-PHY stays powered while the link is only parked in hibern8, so it keeps its
  calibration. Applies: every SoC. Source: jaewun set.
- **1015** RX LINECFG is turned off after link startup, so a UFS device sending bad LineCfg in a
  power mode change cannot wedge the PHY. Applies: every SoC. Source: jaewun set.
- **1016** The UFS lane clock calls enable only the lane clocks, so shared clock counts can reach
  zero in low power. Source: mkp/scsi f07317a8d57f via armada 0533.
- **1017** A UFS device that declines an optional query is not logged as an error or retried.
  Source: mkp/scsi d1fa5cea5dcd via armada 0535.
- **1018** A UFS device that rejects the timestamp attribute stops getting it written on every boot
  and resume. Source: mkp/scsi 00eec343c730 via armada 0536.

### Suspend and wake

- **1006** The gamepad keeps working after resume and the next suspend no longer hangs: non-console
  qcom-geni UART interrupts are masked across suspend. Source: jaewun.
- **1011** qcom-geni serial ports power down in system sleep through forced suspend/resume in the
  system sleep callbacks. Needs: 1006 first. Source: torvalds d0cd9c8d0fd5 via armada 0534.
- **1019** SM8550 no longer wakes straight back up from s2idle: the tsens uplow wake interrupt is
  skipped. Applies: SM8550, gated by `qcom,sm8550`. Source: jaewun, rebased for 7.2's
  suspend-callback wake enable.
- **1023** Suspending a warm device no longer aborts or wakes at once: tsens lower-threshold
  interrupts are masked across suspend. Needs: 1019 (stacks on it). Source: armada 0204.
- **1046, 1047, 1053** Regulator rails take their sleep state in s2idle: rpmh suspend states with
  the PMIC5 bypass mode, the mem state applied in s2idle only for opted-in drivers.
  Applies: rails whose DT node sets a state-mem (opt-in). Source: armada PR #545 (thorch).
- **1052** A rail with no suspend config is logged at debug, not at every suspend.
  Source: armada PR #545 (thorch).
- **1080** Waking with the power button no longer puts the device straight back to sleep:
  pm8941-pwrkey drops the wake press and its release (the first event within 1 s of resume),
  as ACPI buttons do. Source: ours.
- **1091** Active-only (`_ao`) RPMh clocks no longer leave the 38.4 MHz XO crystal forced on
  in s2idle: `clk-rpmh` always programs the sleep state on the first command send so
  `SLEEP_TCS` does not stay at `UINT_MAX`. Source: ours.

### PCIe and wifi

- **1045** SM8550 suspend no longer wedges: the PCIe L2/L3-ready poll is skipped, since PARF_LTSSM
  is unreadable after PME_Turn_Off there. Applies: SM8550 only, gated by `qcom,pcie-sm8550`.
  Source: armada 0512.
- **1048** PCIe keeps a suspend OPP as its memory floor in s2idle. Applies: does nothing without a
  DT suspend OPP, which only sm8550.dtsi has (via sm8550's 1049). Source: armada 0513.
- **1054** The PCIe host can power down in s2idle: only endpoints veto D3cold.
  Applies: every SoC (the sm8250 pcie-qcom path reaches the same D3cold check). Source: armada 0522.
- **1060, 1061** Wifi comes up: pcie-qcom's BDF-to-SID table and the OF devlink parser read the
  five-cell iommu-map that 7.2.6 moved the sm8550 and sm8250 dtsi PCIe nodes to (with four, the
  wifi chip's DMA was unmapped and MHI never came up). Still needed at 7.2.10.
  Source: armada 0514/0514a.
- **1024** The ath12k scan timeout runs as wiphy delayed work. Applies: ath12k SoCs only; sm8250
  does not build ath12k. Source: LKML v4 via armada 1021.

### Video decode (iris)

- **1029** iris caches the work mode it picks, so clock and buffer sizing see the stage in use.
  Source: LKML v9 by Sachin Kumar Garg, via armada PR #752.
- **1030, 1031** Remote Play no longer goes green after Steam restarts the decoder: the H.264 POC
  type the firmware reported is sent back, and the AV1 tier setter no longer overwrites the HEVC
  tier, so the firmware stops raising the same source change. Applies: gen2 only (sm8250 runs
  gen1). Source: armada PR #718 (diogotr7), verbatim.
- **1032** The gen2 VSP clock estimate counts CABAC cost, so high bitrate streams get a clock that
  keeps up. Applies: gen2 only. Trap: it sets `mb_cycles_vsp` in the sm8550 and qcs8300 platform
  headers only, so a new gen2 platform header needs its own or its VSP clock estimate drops the
  per-macroblock term. Source: armada PR #752 (virtudude), verbatim.
- **1033** Decode order is opt-in through the gen2 DISPLAY_DELAY controls. Applies: shared code,
  inert on gen1 (its cap table has no DISPLAY_DELAY entries). Source: armada PR #752 (virtudude),
  verbatim.
- **1034** A session asking for decode order runs in stage 1. Applies: as 1033.
  Source: armada PR #752 (virtudude), verbatim.
- **1035** A session asking for decode order runs at the top video clock. Applies: as 1033.
  Source: armada PR #752 (virtudude), verbatim.
- **1036** Decoder power rescales only on a bitstream queue. Applies: gen1 and gen2.
  Source: armada PR #752 (virtudude), verbatim.
- **1037** Game streams decode with low latency by default: decoder sessions up to the macroblock
  count of 4096x2160 run in stage 1 at the top video clock; `qcom_iris.low_latency=0` restores the
  computed clock and stage 2. Applies: gen1 and gen2 (the RP5 Remote Play freeze once blamed on it
  was Steam's frame-0 restart loop, which 1089 removes). Source: armada PR #752 (virtudude),
  verbatim.
- **1038** Steam's arm64 Remote Play client no longer restarts the decoder every frame: a
  resolution change's empty LAST buffer is no longer also flagged ERROR. Applies: gen2 only.
  Source: kettlelinux 1370 by gennro, via armada PR #752.
- **1087** Steam Remote Play no longer runs the RP5 out of memory and resets it: the input internal
  buffers go back to the firmware when the input queue stops before capture is set up (each
  restart kept the old set and allocated a new one, ~64 MB at 1728x1080). Applies: gen1 (sm8250);
  gen2 unchanged. Source: ours.
- **1088** Remote Play on gen1 no longer stays green: capture setup waits for the first source
  change and finishes from a work item. Applies: gen1 (sm8250); gen2 unchanged. Source: ours.
- **1089** HEVC Remote Play no longer falls back to H.264 on gen1, and H.264 streams no longer
  start frozen: a decoded frame stamped 0 comes back stamped 1 us, since Steam's arm64 client reads
  timestamp 0 as a failed decode and restarts without a keyframe, which gen1 cannot resume from.
  Applies: gen1 (sm8250); gen2 unchanged. Source: ours. Drop: once Steam stops treating 0 as a
  failure.

### GPU and display

- **1066** gamescope no longer paces ~65 fps at a 60 cap on command-mode panels: DPU vblank
  timestamps come from the tear check counter. Applies: command-mode panels; a no-op on video
  mode. Source: armada 0078, verbatim.
- **1076** a6xx GMU messages no longer time out although the GMU answered: the HFI interrupt
  clears only the CM3 fault. Source: kettlelinux 1350, via armada 0620.
- **1077** A GMU timeout in GPU recovery that meets a page fault no longer freezes the display
  until a reboot: the GMU wait for a fault devcoredump is bounded. Source: kettlelinux 1351, via
  armada 0621.
- **1078** The HFI interrupt is masked before the GMU boots, so a late delivery after resume
  cannot race the GMU's first requests. Source: armada 0622.
- **1090** `gmu_rsc` no longer holds stale SH0/MC0/CN0 and ARC rail votes across suspend (which
  blocked CXSD and DDR sleep after any GPU activity): fixes the inverted `GMU_STATUS_FW_START`
  check in `a6xx_rpmh_stop()` and leaves the GPU RSC awake for system poweroff. Source: LKML
  (Shivam Rawat / Michael Burch).

### Battery

- **1082, 1083** Steam shows a time remaining and UPower an energy level on SM8350-class firmware
  (SM8550 included): the charge unit is set to mAh so CHARGE_FULL* stop returning ENODATA, and
  BATT_CHG_COUNTER (the remaining charge there) is also exposed as CHARGE_NOW. Applies: battmgr
  boards; sm8250 builds battmgr but runs qcom_fg. Source: Jan-Michael Brummer's LKML v1 series
  "report charge levels on SM8350-class firmware", 2026-08-29, verbatim. Drop: at a kernel base
  that carries them; swap for a v2 if one is posted.

### FEX (x86 emulation)

- **1062** The kernel emulates unaligned atomics for FEX, which opts in per thread via
  PR_ARM64_SET_UNALIGN_ATOMIC. Needs: the SoC dir's 0504. Source: Billy Laws' LKML RFC v2 as
  ported to 7.2.3 by armada 0505.
- **1067** A 128-bit atomic load on a read-only page no longer oopses the kernel and kills the
  emulated process: its store-exclusive gets a fault entry. Needs: 1062. Source: armada 0505a.

## Not taken

None.

## Retired numbers

None.
