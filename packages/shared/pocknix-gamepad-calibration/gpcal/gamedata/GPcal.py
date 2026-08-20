"""
    GPcal: a gamepad calibration tool for RP 5/Mini
    Author: Kdog
    Version: 0.2
    SPDX-License-Identifier: MIT
"""

import pyxel
import datetime
from pathlib import Path
from Klib.PyxUI import *

CALIBRATE_DETECTION_PERCENT=10  
AXIS_MAX_PERCENT=95             # correction after calc (error margin)
AXIS_DEADZONE_PERCENT=150       # correction after calc (error margin), stick rest zone is wide...
AXIS_DEADZONE_PERCENT_MINI=5
AXIS_ANTIDEADZONE_PERCENT=80    # 0 to 100 (> 50 to avoid big first step)
TRIGGER_MAX_PERCENT=100         # correction after calc (error margin)
TRIGGER_DEADZONE_PERCENT=105    # correction after calc (error margin)
TRIGGER_ANTIDEADZONE_PERCENT=80 # 0 to 100 (> 50 to avoid big first step)
FPS=60
CALIBRATION_DETECTION_FPS = FPS//2    # 0.5s : minimum time to maintain a stick / trigger in a position

TITLE="Kdog GPcal for RP 5/Mini"

class GPCalibrate:
    def __init__(self):
        pyxel.init(320, 240, title=TITLE,fps=FPS, quit_key=pyxel.KEY_ESCAPE, display_scale=1)

        pyxel.load("assets/gpcal.pyxres")
        
        self.ui = []
        self.sdlview = False
        self.exit_frame = 0

        # calibration process stuff
        self.calibrate = False
        self.calibrate_stick = False
        self.calibrate_trigger = False
        self.calibrate_step = 0
        self.calibrate_last_value = None
        self.calibrate_last_value_frame = 0
        self.calibrate_data = [0,0,0,0]  # -max , -min, +min, +max

        # Create UI main panel
        ui_panel = UIPanel(title=TITLE,bcolor=1,selected=1,btitle="made with <3 with Pyxel",btile=0,btile_x=-64,btile_y=-64,btile_w=320+128,btile_h=280+128,btile_colkey=14,btile_rot=30)

        # Create the gamepad object
        self.ui_gamepad = UIGamepad(20,140)
        self.ui_gamepad.select_none()
        self.ui_gamepad.gauge_triggerleft.callback=self.start_calibrate_triggerleft
        self.ui_gamepad.stickleft.callback=self.start_calibrate_stickleft
        self.ui_gamepad.stickright.callback=self.start_calibrate_stickright
        self.ui_gamepad.gauge_triggerright.callback=self.start_calibrate_triggerright

        ui_panel.add_uiobject(self.ui_gamepad)

        # Create the buttons
        self.button_calibrate = UIButton(20,20,60,16,"Calibrate",6, callback=self.start_calibration)
        ui_panel.add_uiobject(self.button_calibrate, True)

        self.button_sdlview = UIButton(90,20,60,16,"SDL view",6, callback=self.toggle_sdl_view)
        ui_panel.add_uiobject(self.button_sdlview)

        self.button_reset = UIButton(160,20,40,16,"Reset",6, callback=self.reset_calibration)
        ui_panel.add_uiobject(self.button_reset)

        self.button_save = UIButton(210,20,40,16,"Save",6, callback=self.save_calibration)
        ui_panel.add_uiobject(self.button_save)

        self.button_quit = UIButton(260,20,40,16,"Quit",6, callback=self.exit)
        ui_panel.add_uiobject(self.button_quit)

        # Create the textbox
        self.ui_textbox_info = UITextbox(20,40,280,30,5,text="Ahoy ! Welcome to Kdog Retroid Pocket Gamepad calibation tool",minshowframe=FPS)
        ui_panel.add_uiobject(self.ui_textbox_info)

        self.ui_textbox_data = UITextbox(20,65,280,70,5,text="")
        ui_panel.add_uiobject(self.ui_textbox_data)

        self.ui.append(ui_panel)

        pyxel.run(self.update, self.draw)

    def exit(self):
        self.ui_textbox_info.minshowframe=0
        self.ui_textbox_info.settext("Sail safe !")
        self.exit_frame = pyxel.frame_count

    def update(self):

        if pyxel.frame_count - self.exit_frame > 30 and self.exit_frame > 0:
            exit()

        if pyxel.btnp(pyxel.GAMEPAD1_BUTTON_B):
            
            if self.calibrate_stick:
                self.ui_textbox_info.settext("Calibration canceled")
                self.stop_calibrate_stick()
                self.ui_gamepad.restore_calibration()
            elif self.calibrate_trigger:
                self.ui_textbox_info.settext("Calibration canceled")
                self.stop_calibrate_trigger()
                self.ui_gamepad.restore_calibration()
            elif self.calibrate:
                self.stop_calibration()
                self.ui_textbox_info.settext("Where to sail now captain ?")

        if self.calibrate_trigger:
            self.run_calibrate_trigger()
        elif self.calibrate_stick:
            self.run_calibrate_stick()

        for _,ui_object in enumerate(self.ui):
            ui_object.update()

        self.ui_textbox_data.settext(self.ui_gamepad.__str__())

    def draw_control_hint(self,x,y):

        pyxel.blt(14, y, 0, 0, 64, 16, 16, 14)      # A button
        pyxel.blt(x+10, y+1, 0, 32, 64, 16, 8, 14)  # OK
        pyxel.blt(x+24, y, 0, 16, 64, 16, 16, 14)   # B buttom
        pyxel.blt(x+34, y+1, 0, 32, 72, 16, 8, 14)  # BACL

        pyxel.blt(x+56, y+1, 0, 48, 72, 16, 8, 14)      # DPAD left
        pyxel.blt(x+63, y-3, 0, 48, 72, 16, 8, 14,90)   # DPAD down
        pyxel.blt(x+70, y+3, 0, 48, 72, 16, 8, 14,-90)  # DPAD up
        pyxel.blt(x+77, y+1, 0, 48, 72, -16, 8, 14)     # DPAD right
        pyxel.blt(x+94, y+1, 0, 48, 64, 16, 8, 14)      # NAV

    def draw(self):
        pyxel.cls(0)

        for _,ui_object in enumerate(self.ui):
            ui_object.draw()
        
        self.draw_control_hint(14,225)
        
    def save_calibration(self):
        savepath = Path.home() / ".config" / "autostart"
        savepath.mkdir(parents=True,exist_ok=True)
        savepath = savepath / "GPcal.sh"
        self.ui_gamepad.calibration.save_configuration(savepath)
        savepath.chmod(0o777)
        self.ui_textbox_info.settext(f"Calibration data saved to")
        self.ui_textbox_info.settext(f"{savepath}")
        self.ui_textbox_info.settext("Where to sail now captain ?")

    def reset_calibration(self):
        self.ui_gamepad.calibration.reset_all()
        self.ui_textbox_info.settext("Calibration data reset to default")
        self.ui_textbox_info.settext("Where to sail now captain ?")

    def toggle_sdl_view(self):
        self.ui_gamepad.toggle_sdl_view()
        self.sdlview = not self.sdlview
        if self.sdlview:
            self.button_sdlview.settext("RAW view")
        else:
            self.button_sdlview.settext("SDL view")

    def start_calibration(self):
        self.calibrate = True
        for _,ui_object in enumerate(self.ui):
            ui_object.select_none()
        self.ui_gamepad.select_first()
        self.ui_textbox_info.settext("Which control do you want to calibrate ?")
    
    def stop_calibration(self):
        self.calibrate = False
        self.ui_gamepad.select_none()
        for _,ui_object in enumerate(self.ui):
            ui_object.select_first()
            break
        self.ui_textbox_info.settext("Where to sail now captain ?")
    
    def start_calibrate_init(self):
        self.ui_gamepad.backup_calibration()
        self.calibrate_data = [0,0,0,0]
        self.ui_gamepad.disable_selection()
        self.calibrate_step = 0

    def stop_calibrate_clean(self):
        self.calibrate_data = [0,0,0,0]
        self.ui_gamepad.enable_selection()
        self.calibrate_step = 0

        self.ui_textbox_info.settext("Which control do you want to calibrate ?")

    def start_calibrate_stickleft(self):
        self.start_calibrate_init()
        self.ui_gamepad.stickleft.reset_measurements()
        self.calibrate_stick = True
        self.ui_gamepad.calibration.reset_axis_left()
        self.calibrate_target = self.ui_gamepad.stickleft
        self.calibrate_target.axis_x.enable_hooking_positive()

    def start_calibrate_stickright(self):
        self.start_calibrate_init()
        self.ui_gamepad.stickright.reset_measurements()
        self.calibrate_stick = True
        self.ui_gamepad.calibration.reset_axis_right()
        self.calibrate_target = self.ui_gamepad.stickright
        self.calibrate_target.axis_x.enable_hooking_positive()

    def stop_calibrate_stick(self):
        self.calibrate_target.axis_x.disable_hooking()
        self.calibrate_target.axis_y.disable_hooking()
        self.stop_calibrate_clean()
        self.calibrate_stick = False

    def start_calibrate_triggerleft(self):
        self.start_calibrate_init()
        self.ui_gamepad.gauge_triggerleft.reset_measurements()
        self.calibrate_trigger = True
        self.ui_gamepad.calibration.reset_trigger_left()
        self.calibrate_target = self.ui_gamepad.gauge_triggerleft
        self.calibrate_target.axis.enable_hooking_positive()

    def start_calibrate_triggerright(self):
        self.start_calibrate_init()
        self.ui_gamepad.gauge_triggerright.reset_measurements()
        self.calibrate_trigger = True
        self.ui_gamepad.calibration.reset_trigger_right()
        self.calibrate_target = self.ui_gamepad.gauge_triggerright
        self.calibrate_target.axis.enable_hooking_positive()

    def stop_calibrate_trigger(self):
        self.calibrate_target.axis.disable_hooking()
        self.stop_calibrate_clean()
        self.calibrate_trigger = False

    def run_calibrate_stick(self):

        if self.calibrate_step == 0:
            print(self.calibrate_data)
            self.ui_textbox_info.settext(f"Step 1/4: Push {self.calibrate_target.name} full {self.calibrate_target.axis_x.positive_indication} few seconds and release")
            self.calibrate_step = 1

        elif self.calibrate_step == 1:
            if self.calibrate_target.axis_x.max != None and self.calibrate_target.axis_x.min != None:
                self.calibrate_data[3] = self.calibrate_target.axis_x.max
                self.calibrate_data[2] = self.calibrate_target.axis_x.min
                print(self.calibrate_data)

                self.calibrate_target.axis_x.disable_hooking()
                self.calibrate_target.axis_x.reset_measurements()
                self.calibrate_target.axis_x.enable_hooking_negative()

                self.ui_textbox_info.settext(f"Step 2/4: Push {self.calibrate_target.name} full {self.calibrate_target.axis_x.negative_indication} few seconds and release")
                self.calibrate_step = 2


        elif self.calibrate_step == 2:
            if self.calibrate_target.axis_x.min != None and self.calibrate_target.axis_x.max != None:
                self.calibrate_data[1] = self.calibrate_target.axis_x.min
                self.calibrate_data[0] = self.calibrate_target.axis_x.max
                print(self.calibrate_data)

                self.calibrate_target.axis_x.reset_measurements()
                self.calibrate_target.axis_x.disable_hooking()

                self.calibrate_step = 3

        elif self.calibrate_step == 3:

            if self.calibrate_data[3] == self.calibrate_target.axis_x.calibration.max\
                and self.calibrate_data[2] == 0 \
                and self.calibrate_data[1] == self.calibrate_target.axis_x.calibration.min  \
                and self.calibrate_data[0] == 0:
                # nothing to do it's perfect !
                pass
            else:
                self.calibrate_data[3] = self.calibrate_data[3] #/ 3  # average
                self.calibrate_data[2] = self.calibrate_data[2] #/ 3  # average
                self.calibrate_data[1] = self.calibrate_data[1] #/ 3  # average
                self.calibrate_data[0] = self.calibrate_data[0] #/ 3  # average

                axis_center = (self.calibrate_data[2] + self.calibrate_data[0]) / 2

                self.calibrate_data[3] = self.calibrate_data[3] - axis_center   # recenter
                self.calibrate_data[2] = self.calibrate_data[2] - axis_center   # recenter
                self.calibrate_data[1] = self.calibrate_data[1] - axis_center   # recenter
                self.calibrate_data[0] = self.calibrate_data[0] - axis_center   # recenter

                axis_max = AXIS_MAX_PERCENT * min(abs(self.calibrate_data[1]), self.calibrate_data[3]) / 100
                deadzone = AXIS_DEADZONE_PERCENT * (abs(self.calibrate_data[0]) + abs(self.calibrate_data[2])) / 200
                if (100 * deadzone / axis_max) < AXIS_DEADZONE_PERCENT_MINI:
                    deadzone = AXIS_DEADZONE_PERCENT_MINI * axis_max / 100

                self.calibrate_target.axis_x.calibration.max = int(axis_max)
                self.calibrate_target.axis_x.calibration.min = -int(axis_max)
                self.calibrate_target.axis_x.calibration.center = - int(axis_center)
                self.calibrate_target.axis_x.calibration.deadzone  = int(deadzone)

                self.calibrate_target.axis_x.calibration.antideadzone = int(AXIS_ANTIDEADZONE_PERCENT * deadzone / 100)

            self.calibrate_data = [0,0,0,0]
            self.calibrate_target.axis_y.reset_measurements()
            self.calibrate_target.axis_y.enable_hooking_positive()
            self.ui_textbox_info.settext(f"Step 3/4: Push {self.calibrate_target.name} full {self.calibrate_target.axis_y.positive_indication} few seconds and release")
            self.calibrate_step = 4

        elif self.calibrate_step == 4:
            if self.calibrate_target.axis_y.max != None and self.calibrate_target.axis_y.min != None:
                self.calibrate_data[3] = self.calibrate_target.axis_y.max
                self.calibrate_data[2] = self.calibrate_target.axis_y.min
                print(self.calibrate_data)

                self.calibrate_target.axis_y.disable_hooking()
                self.calibrate_target.axis_y.reset_measurements()
                self.calibrate_target.axis_y.enable_hooking_negative()

                self.ui_textbox_info.settext(f"Step 4/4: Push {self.calibrate_target.name} full {self.calibrate_target.axis_y.negative_indication} few seconds and release")
                self.calibrate_step = 5


        elif self.calibrate_step == 5:
            if self.calibrate_target.axis_y.min != None and self.calibrate_target.axis_y.max != None:
                self.calibrate_data[1] = self.calibrate_target.axis_y.min
                self.calibrate_data[0] = self.calibrate_target.axis_y.max
                print(self.calibrate_data)

                self.calibrate_target.axis_y.reset_measurements()
                self.calibrate_target.axis_y.disable_hooking()

                self.calibrate_step = 6

        elif self.calibrate_step == 6:
            if self.calibrate_data[3] == self.calibrate_target.axis_y.calibration.max\
                and self.calibrate_data[2] == 0 \
                and self.calibrate_data[1] == self.calibrate_target.axis_y.calibration.min  \
                and self.calibrate_data[0] == 0:
                # nothing to do it's perfect !
                pass
            else:
                self.calibrate_data[3] = self.calibrate_data[3]
                self.calibrate_data[2] = self.calibrate_data[2]
                self.calibrate_data[1] = self.calibrate_data[1]
                self.calibrate_data[0] = self.calibrate_data[0]

                axis_center = (self.calibrate_data[2] + self.calibrate_data[0]) / 2

                self.calibrate_data[3] = self.calibrate_data[3] - axis_center   # recenter
                self.calibrate_data[2] = self.calibrate_data[2] - axis_center   # recenter
                self.calibrate_data[1] = self.calibrate_data[1] - axis_center   # recenter
                self.calibrate_data[0] = self.calibrate_data[0] - axis_center   # recenter

                axis_max = AXIS_MAX_PERCENT * min(abs(self.calibrate_data[1]), self.calibrate_data[3]) / 100
                deadzone = AXIS_DEADZONE_PERCENT * (abs(self.calibrate_data[0]) + abs(self.calibrate_data[2])) / 200
                if (100 * deadzone / axis_max) < AXIS_DEADZONE_PERCENT_MINI:
                    deadzone = AXIS_DEADZONE_PERCENT_MINI * axis_max / 100

                self.calibrate_target.axis_y.calibration.max = int(axis_max)
                self.calibrate_target.axis_y.calibration.min = -int(axis_max)
                self.calibrate_target.axis_y.calibration.center = - int(axis_center)
                self.calibrate_target.axis_y.calibration.deadzone  = int(deadzone)

                self.calibrate_target.axis_y.calibration.antideadzone = int(AXIS_ANTIDEADZONE_PERCENT * deadzone / 100)

            self.calibrate_step = 7

        elif self.calibrate_step == 7:
            #self.ui_gamepad.calibration.update_params = 1
            self.ui_gamepad.calibration.write_parameters()
            self.ui_textbox_info.settext("Calibration done")
            self.stop_calibrate_stick()

    def run_calibrate_trigger(self):

        if self.calibrate_step == 0:
            print(self.calibrate_data)
            self.ui_textbox_info.settext(f"Push {self.calibrate_target.name} full {self.calibrate_target.axis.positive_indication} few seconds and release")
            self.calibrate_step = 1

        elif self.calibrate_step == 1:
            if self.calibrate_target.axis.max != None and self.calibrate_target.axis.min != None:
                self.calibrate_data[3] = self.calibrate_target.axis.max
                self.calibrate_data[2] = self.calibrate_target.axis.min
                print(self.calibrate_data)

                self.calibrate_target.axis.disable_hooking()
                self.calibrate_target.axis.reset_measurements()
                self.calibrate_step = 2

        elif self.calibrate_step == 2:

            maxvalue = self.calibrate_data[3] - self.calibrate_data[2]
            maxvalue = TRIGGER_MAX_PERCENT * maxvalue / 100
            deadzone = (TRIGGER_DEADZONE_PERCENT - 100) * self.calibrate_data[2] / 100

            self.calibrate_target.axis.calibration.max  = int(maxvalue)
            self.calibrate_target.axis.calibration.deadzone  = int(deadzone)
            self.calibrate_target.axis.calibration.antideadzone = int(TRIGGER_ANTIDEADZONE_PERCENT * deadzone / 100)
            
            self.calibrate_data = [0,0,0,0]
            self.calibrate_step = 4

        elif self.calibrate_step == 4:
            #self.ui_gamepad.calibration.update_params = 1
            self.ui_gamepad.calibration.write_parameters()
            self.ui_textbox_info.settext("Calibration done")
            self.stop_calibrate_trigger()
