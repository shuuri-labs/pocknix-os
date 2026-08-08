"""
    RPocket: a library for Retroid Pocket (5/Mini)
    Author: Kdog
    Version: 0.2
    SPDX-License-Identifier: MIT
"""

import pyxel
from pathlib import Path
import sys

# Default value used when calibration is reset
# DEFAULT_AXIS_MAX : this one is not critical as it only
# impacts the SDL layer (truncate the value) and it will be
# updated during the calibration procedure with an optimal
# value
DEFAULT_AXIS_MAX=0x580
# DEFAULT_TRIGGER_MAX: this one is tricky because the reported value
# from the driver for a trigger is modified with it. The simplified 
# formula is trigger = max(TRIGGER_MAX - raw_value, 0)
# If the value is too low, the range of the trigger is decimated.
# It's better to chose a too big value which will be lowered during
# the calibration procedure.
DEFAULT_TRIGGER_MAX=0x755

PARAMETERS_DIR_PATH="/sys/module/retroid/parameters"

class Axis:
    def __init__(self,calibration,pname="leftx",name="Left X", orientation="h"):
        self.calibration=calibration
        self.pname=pname
        self.name=name
        self.orientation=orientation
        self.value=0
        self.value_frame=pyxel.frame_count
        self.sdl_percent=0
        self.max=None
        self.min=None

        self.hooking_positive=False
        self.hooking_negative=False

        if orientation == "h":
            self.positive_indication="right"
            self.negative_indication="left"
        elif self.orientation == "v":
            self.positive_indication="down"
            self.negative_indication="up"
        else:
            self.positive_indication="positive"
            self.negative_indication="negative"
    
    def update_value(self,value):
        self.value = value
        self.value_frame = pyxel.frame_count
        self.sdl_percent = 100 * self.value / (self.calibration.max - self.calibration.antideadzone)
        #print(f"{self.pname} = {value}")

    def update(self):

        if self.hooking_positive:
            if pyxel.frame_count - self.value_frame == self.hooking_frames:
                if 2 * self.value < self.calibration.max and self.max != None:
                    # minimum should be less than 50% of the max value
                    if self.min == None:
                        self.min = self.value
                    else:
                        self.min = min(self.min,self.value)

                    pyxel.play(0,0)
                
                elif 2* self.value > self.calibration.max:
                    # maximum should be more than 50% of the max value
                    if self.max == None:
                        self.max = self.value
                    else:            
                        self.max = max(self.max,self.value)
                    
                    pyxel.play(0,0)
                
        elif self.hooking_negative:
            if pyxel.frame_count - self.value_frame == self.hooking_frames:
                if 2* abs(self.value) < self.calibration.max and self.min != None:
                    # maximum should be less than 50% of the max value
                    if self.max == None:
                        self.max = self.value
                    else:            
                        self.max = min(self.max,self.value)
                    
                    pyxel.play(0,0)

                elif 2 * self.value < self.calibration.min:
                    # minimum should be lower than 50% of the min value
                    if self.min == None:
                        self.min = self.value
                    else:
                        self.min = min(self.min,self.value)
                    
                    pyxel.play(0,0)

        else:
            
            if self.min == None:
                self.min = self.value
            else:
                self.min = min(self.min,self.value)
            
            if self.max == None:
                self.max = self.value
            else:            
                self.max = max(self.max,self.value)


    def reset_measurements(self):
        self.max = None
        self.min = None

    def enable_hooking_positive(self,frames=30):
        self.last_hooking_frame=0
        self.hooking_frames=frames
        self.hooking_positive = True
        self.reset_measurements()
    
    def enable_hooking_negative(self,frames=30):
        self.last_hooking_frame=0
        self.hooking_frames=frames
        self.hooking_negative = True
        self.reset_measurements()

    def get_hooking_progress(self):
        if self.hooking_negative or self.hooking_positive:
            return min((pyxel.frame_count - self.value_frame) / self.hooking_frames, 1 )
        else:
            return -1
    
    def disable_hooking(self):
        self.hooking_negative = False
        self.hooking_positive = False
        self.last_hooking_frame=0

    def __str__(self):
        if self.min == None:
            minimum = f"{'-':^5}"
        else:
            minimum = f"{self.min:#5}"

        if self.max == None:
            maximum = f"{'-':^5}"
        else:
            maximum = f"{self.max:#5}"

        try:
            cal_center=f"{self.calibration.center:^5}"
        except AttributeError:
            cal_center=f"{'n/a':^5}"
        
        try:
            cal_minimum=f"{self.calibration.min:^5}"
        except AttributeError:
            cal_minimum=f"{'n/a':^5}"

        return f"{self.pname:<15}|{self.value:#5}|{minimum}|{maximum}|" \
                + f"{cal_center}|{self.calibration.deadzone:^5}|" \
                + f"{self.calibration.antideadzone:^5}|{cal_minimum}|" \
                + f"{self.calibration.max:^5}|\n"


class RPCalibrationControl:
    def __init__(self, parameters_dir, name, default_max):
        self.name=name
        self.parameters_dir = Path(parameters_dir)
        self.default_max = default_max
        self.antideadzone = 0
        self.deadzone = 0
        self.max = 0

    def load_parameters(self):
        try:
            with open(self.parameters_dir / f"{self.name}_antideadzone","r") as fparam:
                self.antideadzone = int(fparam.readline())
            with open(self.parameters_dir / f"{self.name}_deadzone","r") as fparam:
                self.deadzone = int(fparam.readline())
            with open(self.parameters_dir / f"{self.name}_max","r") as fparam:
                self.max = int(fparam.readline())

        except IOError as e:
            print(f"I/O error({e.errno}): {e.strerror}")
            exit(1)
        except: #handle other exceptions such as attribute errors
            print(f"Unexpected error:{sys.exc_info()[0]}")
            exit(1)

    def save_configuration(self, savefile):
        
        savefile.write(f"echo {self.antideadzone} > {self.parameters_dir}/{self.name}_antideadzone\n")
        savefile.write(f"echo {self.deadzone} > {self.parameters_dir}/{self.name}_deadzone\n")
        savefile.write(f"echo {self.max} > {self.parameters_dir}/{self.name}_max\n")
    
    def write_parameters(self):
        
        try:
            with open(self.parameters_dir / f"{self.name}_antideadzone","w") as fparam:
                fparam.write(f"{self.antideadzone}")

            with open(self.parameters_dir / f"{self.name}_deadzone","w") as fparam:
                fparam.write(f"{self.deadzone}")
                    
            with open(self.parameters_dir / f"{self.name}_max","w") as fparam:
                fparam.write(f"{self.max}")

        except IOError as e:
            print(f"I/O error({e.errno}): {e.strerror}")
            exit(1)
        except: #handle other exceptions such as attribute errors
            print(f"Unexpected error:{sys.exc_info()[0]}")
            exit(1)
    
    def get_range(self):
        return self.max - self.antideadzone
    
    def reset(self):
        self.antideadzone = 0
        self.deadzone = 0
        self.max = self.default_max

    def __str__(self):
        result = f"{self.name}_antideadzone={self.antideadzone}\n"
        result += f"{self.name}_deadzone={self.deadzone}\n"
        result += f"{self.name}_max={self.max}\n"

        return result

class RPCalibrationAxis(RPCalibrationControl):
    def __init__(self, parameters_dir, name="axis_leftx", default_max=DEFAULT_AXIS_MAX):
        super().__init__(parameters_dir, name, default_max)
        self.min = -default_max
        self.center = 0
        self.load_parameters()

    def load_parameters(self):
        
        super().load_parameters()
        try:
            with open(self.parameters_dir / f"{self.name}_center","r") as fparam:
                self.center = int(fparam.readline())
            with open(self.parameters_dir / f"{self.name}_min","r") as fparam:
                self.min = int(fparam.readline())

        except IOError as e:
            print(f"I/O error({e.errno}): {e.strerror}")
            exit(1)
        except: #handle other exceptions such as attribute errors
            print(f"Unexpected error:{sys.exc_info()[0]}")
            exit(1)
    
    def save_configuration(self, savefile):
        super().save_configuration(savefile)
        savefile.write(f"echo {self.center} > {self.parameters_dir}/{self.name}_center\n")
        savefile.write(f"echo {self.min} > {self.parameters_dir}/{self.name}_min\n")
    
    def write_parameters(self):
        super().write_parameters()
        try:
            with open(self.parameters_dir / f"{self.name}_center","w") as fparam:
                fparam.write(f"{self.center}")
            with open(self.parameters_dir / f"{self.name}_min","w") as fparam:
                fparam.write(f"{self.min}")

        except IOError as e:
            print(f"I/O error({e.errno}): {e.strerror}")
            exit(1)
        except: #handle other exceptions such as attribute errors
            print(f"Unexpected error:{sys.exc_info()[0]}")
            exit(1)

    def reset(self):
        super().reset()
        self.center = 0
        self.min = -self.default_max
    
    def __str__(self):
        result = super().__str__()
        result += f"{self.name}_center={self.center}\n"
        result += f"{self.name}_min={self.min}\n"

        return result

class RPCalibrationTrigger(RPCalibrationControl):
    def __init__(self, parameters_dir, name="trigger_left", default_max=DEFAULT_TRIGGER_MAX):
        super().__init__(parameters_dir, name, default_max)
        self.load_parameters()
    
class RPCalibration:
    def __init__(self, parameters_dir=PARAMETERS_DIR_PATH, default_axis_max=DEFAULT_AXIS_MAX, default_trigger_max=DEFAULT_TRIGGER_MAX):
        self.parameters_dir = Path(parameters_dir)

        if not self.parameters_dir.exists():
            self.create_fake()
            
        self.axis_leftx = RPCalibrationAxis(self.parameters_dir,"axis_leftx",default_axis_max)
        self.axis_lefty = RPCalibrationAxis(self.parameters_dir,"axis_lefty",default_axis_max)
        self.axis_rightx = RPCalibrationAxis(self.parameters_dir,"axis_rightx",default_axis_max)
        self.axis_righty = RPCalibrationAxis(self.parameters_dir,"axis_righty",default_axis_max)
        self.trigger_left = RPCalibrationTrigger(self.parameters_dir,"trigger_left",default_trigger_max)
        self.trigger_right = RPCalibrationTrigger(self.parameters_dir,"trigger_right",default_trigger_max)

        self.load_parameters()

    def create_fake(self):
        self.parameters_dir = Path("/tmp") / "rpcal.fake"
        self.parameters_dir.mkdir(parents=True,exist_ok=True)

        for axis in [ "axis_leftx", "axis_lefty", "axis_rightx", "axis_righty" ]:
            # min / max / center / deadzone / antideadzone
            with open(self.parameters_dir / f"{axis}_min", "w") as parameter:
                parameter.write(f"-{DEFAULT_AXIS_MAX}")
            with open(self.parameters_dir / f"{axis}_max", "w") as parameter:
                parameter.write(f"{DEFAULT_AXIS_MAX}")
            with open(self.parameters_dir / f"{axis}_center", "w") as parameter:
                parameter.write("0")
            with open(self.parameters_dir / f"{axis}_deadzone", "w") as parameter:
                parameter.write("0")
            with open(self.parameters_dir / f"{axis}_antideadzone", "w") as parameter:
                parameter.write("0")
        
        for trigger in [ "trigger_left", "trigger_right" ]:
            # min / max / center / deadzone / antideadzone
            with open(self.parameters_dir / f"{trigger}_max", "w") as parameter:
                parameter.write(f"{DEFAULT_AXIS_MAX}")
            with open(self.parameters_dir / f"{trigger}_deadzone", "w") as parameter:
                parameter.write("0")
            with open(self.parameters_dir / f"{trigger}_antideadzone", "w") as parameter:
                parameter.write("0")
        
        with open(self.parameters_dir / "update_params", "w") as parameter:
            parameter.write("0")

    def load_parameters(self):
        try:
            with open(self.parameters_dir / "update_params","r") as fparam:
                self.update_params = int(fparam.readline())

        except IOError as e:
            print(f"I/O error({e.errno}): {e.strerror}")
            exit(1)
        except: #handle other exceptions such as attribute errors
            print(f"Unexpected error:{sys.exc_info()[0]}")
            exit(1)

    def save_configuration(self, savepath):
        with open(savepath,"w") as savefile:
            savefile.write("#!/usr/bin/env bash\n")
            savefile.write("#\n")
            savefile.write("# Retroid Pocket 5/Mini gamepad calibration\n")
            savefile.write("# Made with the Kdog GPcal tool\n")
            savefile.write("# SPDX-License-Identifier: MIT\n")
            savefile.write("#\n")
            self.axis_leftx.save_configuration(savefile)
            self.axis_lefty.save_configuration(savefile)
            self.axis_rightx.save_configuration(savefile)
            self.axis_righty.save_configuration(savefile)
            self.trigger_left.save_configuration(savefile)
            self.trigger_right.save_configuration(savefile)
            savefile.write(f"echo 1 > {self.parameters_dir}/update_params\n")

    def write_parameters(self):
        self.axis_leftx.write_parameters()
        self.axis_lefty.write_parameters()
        self.axis_rightx.write_parameters()
        self.axis_righty.write_parameters()
        self.trigger_left.write_parameters()
        self.trigger_right.write_parameters()
        self.update_params=1
        try:
            with open(self.parameters_dir / "update_params","w") as fparam:
                fparam.write(f"{self.update_params}")
        except IOError as e:
            print(f"I/O error({e.errno}): {e.strerror}")
            exit(1)
        except: #handle other exceptions such as attribute errors
            print(f"Unexpected error:{sys.exc_info()[0]}")
            exit(1)

        self.update_params=0


    def reset_axis_left(self):
        self.axis_leftx.reset()
        self.axis_lefty.reset()
        self.write_parameters()
    
    def reset_axis_right(self):
        self.axis_rightx.reset()
        self.axis_righty.reset()
        self.write_parameters()

    def reset_trigger_left(self):
        self.trigger_left.reset()
        self.write_parameters()

    def reset_trigger_right(self):
        self.trigger_right.reset()
        self.write_parameters()
      
    def reset_all(self):
        self.axis_leftx.reset()
        self.axis_lefty.reset()
        self.axis_rightx.reset()
        self.axis_righty.reset()
        self.trigger_left.reset()
        self.trigger_right.reset()
        self.write_parameters()
    
    def __str__(self):
        return self.axis_leftx \
            + self.axis_lefty \
            + self.axis_rightx \
            + self.axis_righty \
            + self.trigger_left \
            + self.trigger_right \
            +f"self.update_params={self.update_params}\n"
