## 📂 Project Structure & Branch Strategy

This project is organized into modular branches to ensure separation of concerns between hardware control logic and the software interface. Please navigate to the relevant branch to view the source code:

* *board1 (Air Conditioner System):* Contains the Assembly code for the *Air Conditioner Control Unit* (Board #1). This module manages temperature sensing, keypad inputs, and heater/cooler simulation logic.
* *board2 (Curtain & Environment System):* Contains the Assembly code for the *Curtain Control & Monitoring Unit* (Board #2). This module handles the BMP180 sensor, LDR light sensor, and stepper motor control.
* *api (PC Interface):* Contains the *Python API and User Interface*. This module implements the UART communication protocol to interact with both boards and provides a console-based dashboard for control.

> *Note:* To view the code, please select the corresponding branch from the dropdown menu above or use git checkout <branch_name>
