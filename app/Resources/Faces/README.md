Optional photo faces. The public repository ships none. If you add your own
`face_12c_nolcd.png`, `face_15c_nolcd.png` and `face_16c_nolcd.png` here (straight-on photos with an
empty LCD, geometry in `app/Sources/Models/PhotoFaceGeometry.swift`, made with `art/tools/`) and run
`python3 app/tools/genproj.py`, the app uses them; without them it draws the calculator itself.
