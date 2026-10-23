# MTT Input Bridge - third-party notices

## OpenTabletDriver

The tablet database (`src/otd/otd_devices.cpp`) and the pen report parsers and device
matching rules (`src/otd/otd.cpp`, `src/otd/otd.hpp`) of this extension are derived from
OpenTabletDriver, https://github.com/OpenTabletDriver/OpenTabletDriver, by InfinityGhost,
X9VoiD and the OpenTabletDriver contributors.

OpenTabletDriver is licensed under the GNU Lesser General Public License, version 3 only
(LGPL-3.0-only). The derived files above are distributed under the same licence; the
licence texts are `LICENSE.LGPL-3.0` and `LICENSE.GPL-3.0` (the LGPL incorporates the GPL).
The rest of MTT Input Bridge is not derived from OpenTabletDriver.

The source code of the derived files, including any modifications, and the material
needed to rebuild and relink the extension with a modified version of them, is available
at: https://raw.githubusercontent.com/MattiaPersico/MTT/main/Extensions/tablet_bridge/0.3.1/mtt_input_bridge-source.zip

The OpenTabletDriver commit the database was generated from is printed by the action
"MTT: Input Bridge - diagnostics".
