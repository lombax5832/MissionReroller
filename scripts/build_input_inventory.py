"""Package a passive Lua API inventory; never calls discovered engine methods."""
import sys
from pathlib import Path
import build_core as build
MODULE='mods/ipodalexei/mission_reroller_input_inventory'
GUID='64a7fb1b-962a-4733-b48e-52183def07f3'
SOURCE=build.ROOT/'src'/(MODULE+'.lua')
def main(output=None):
    output=Path(output) if output else build.ROOT/'releases/Mission-Reroller-Input-Inventory-v0.1.0.zip'
    build.build_addon(MODULE,SOURCE.read_bytes(),GUID,output,'Mission Reroller Input Inventory v0.1.0 (read only)')
    print(output);return output
if __name__=='__main__':main(sys.argv[1] if len(sys.argv)>1 else None)
