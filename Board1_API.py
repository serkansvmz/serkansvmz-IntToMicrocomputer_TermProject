import serial
import time
import struct
import sys

# =============================================================================
# AYARLAR
# =============================================================================
PORT_AC = 'COM10'  # Board #1 (Klima)
PORT_CURTAIN = 'COM11'  # Board #2 (Perde)
BAUD_RATE = 9600  # Simülasyon hızı


# =============================================================================
# API CLASSES
# =============================================================================

class HomeAutomationSystemConnection:
    def __init__(self, port_name):
        self.ser = None
        self.comPort = port_name
        self.baudRate = BAUD_RATE

    def open(self):
        try:
            self.ser = serial.Serial(self.comPort, self.baudRate, timeout=2)
            print(f"[BAĞLANTI] {self.comPort} açıldı.")
            return True
        except Exception as e:
            print(f"[HATA] {self.comPort} açılamadı: {e}")
            return False

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
            print(f"[BAĞLANTI] {self.comPort} kapatıldı.")

    def send_byte(self, byte_val):
        if self.ser and self.ser.is_open:
            self.ser.write(bytes([byte_val]))
            time.sleep(0.05)

    def read_byte(self):
        if self.ser and self.ser.is_open:
            val = self.ser.read(1)
            if val:
                return int.from_bytes(val, byteorder='big')
        return 0

    def setComPort(self, port):
        self.comPort = port

    def setBaudRate(self, rate):
        self.baudRate = rate

    def update(self):
        pass


class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    def __init__(self, port):
        super().__init__(port)
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def update(self):
        # 1. Ortam Sicakligi
        self.send_byte(0x04)
        amb_int = self.read_byte()
        self.send_byte(0x03)
        amb_frac = self.read_byte()
        self.ambientTemperature = float(f"{amb_int}.{amb_frac}")

        # 2. İstenen Sıcaklık
        self.send_byte(0x02)
        des_int = self.read_byte()
        self.send_byte(0x01)
        des_frac = self.read_byte()
        self.desiredTemperature = float(f"{des_int}.{des_frac}")

        # 3. Fan Hızı
        self.send_byte(0x05)
        self.fanSpeed = self.read_byte()

    def setDesiredTemp(self, temp):
        str_temp = f"{temp:.1f}"
        parts = str_temp.split('.')
        val_int = int(parts[0])
        val_frac = int(parts[1])
        if val_int > 63: val_int = 63
        if val_frac > 9: val_frac = 9

        self.send_byte(0xC0 | val_int)
        time.sleep(0.05)
        self.send_byte(0x80 | val_frac)
        return True

    def getAmbientTemp(self):
        return self.ambientTemperature

    def getDesiredTemp(self):
        return self.desiredTemperature

    def getFanSpeed(self):
        return self.fanSpeed


class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    def __init__(self, port):
        super().__init__(port)
        self.curtainStatus = 0.0
        self.outdoorTemperature = 0.0
        self.outdoorPressure = 0.0
        self.lightIntensity = 0.0

    def update(self):
        # 1. Curtain Status
        self.send_byte(0x02)
        c_int = self.read_byte()
        self.send_byte(0x01)
        c_frac = self.read_byte()
        self.curtainStatus = float(f"{c_int}.{c_frac}")

        # 2. Outdoor Temp
        self.send_byte(0x04)
        t_int = self.read_byte()
        self.send_byte(0x03)
        t_frac = self.read_byte()
        self.outdoorTemperature = float(f"{t_int}.{t_frac}")

        # 3. Outdoor Pressure (DÜZELTİLDİ: PIC ile %100 Uyumlu Hesaplama)
        self.send_byte(0x06)  # Get High
        p_int = self.read_byte()
        self.send_byte(0x05)  # Get Low
        p_frac = self.read_byte()

        # --- PIC ASSEMBLY TAKLİT ALGORİTMASI ---
        # PIC kodu: (Raw * 1.5) işlemini yaparken 8-bit taşması yaşıyor.
        # Biz de aynısını yapıyoruz:
        raw_val = p_int
        calc_val = int(raw_val * 1.5)

        # 8-bit Taşma (Overflow) Simülasyonu
        calc_val = calc_val % 256

        # PIC Kodu: 150'den büyükse 150'ye sabitle
        if calc_val > 150:
            calc_val = 150

        # PIC Kodu: 50 ekle
        calc_val += 50

        # PIC Kodu: LCD'ye "10" yaz, sonra Yüzler ve Onlar basamağını yaz (Birler yok!)
        # Örn: calc_val=95 ise -> Yüzler=0, Onlar=9 -> Ekrana "1009" yazar.
        hundreds = (calc_val // 100) % 10
        tens = (calc_val // 10) % 10

        # LCD'de görünen stringi oluşturup sayıya çeviriyoruz
        final_str = f"10{hundreds}{tens}"
        self.outdoorPressure = float(final_str)

        # 4. Light Intensity
        self.send_byte(0x08)
        l_int = self.read_byte()
        self.send_byte(0x07)
        l_frac = self.read_byte()
        self.lightIntensity = float(f"{l_int}.{l_frac}")

    def setCurtainStatus(self, status):
        str_val = f"{status:.1f}"
        parts = str_val.split('.')
        val_int = int(parts[0])
        val_frac = int(parts[1])
        if val_int > 100: val_int = 100

        try:
            # 2-Byte Protokolü (Header + Data)
            self.send_byte(0xC0)  # Header High
            time.sleep(0.05)
            self.send_byte(val_int)  # Data High
            time.sleep(0.05)

            self.send_byte(0x80)  # Header Low
            time.sleep(0.05)
            self.send_byte(val_frac)  # Data Low
            return True
        except:
            return False

    def getOutdoorTemp(self):
        return self.outdoorTemperature

    def getOutdoorPress(self):
        return self.outdoorPressure

    def getLightIntensity(self):
        return self.lightIntensity


# =============================================================================
# APPLICATION MENU
# =============================================================================

def main_menu():
    print("Sistem Başlatılıyor...")
    ac_system = AirConditionerSystemConnection(PORT_AC)
    curtain_system = CurtainControlSystemConnection(PORT_CURTAIN)

    # Hata almamak için try-connect
    try:
        ac_system.open()
    except:
        pass

    try:
        curtain_system.open()
    except:
        pass

    while True:
        print("\n" + "=" * 40)
        print("      MAIN MENU")
        print("=" * 40)
        print("1. Air Conditioner (Board #1)")
        print("2. Curtain Control (Board #2)")
        print("3. Exit")

        choice = input("Seçiminiz: ")

        if choice == '1':
            air_conditioner_menu(ac_system)
        elif choice == '2':
            curtain_control_menu(curtain_system)
        elif choice == '3':
            ac_system.close()
            curtain_system.close()
            break
        else:
            print("Geçersiz seçim!")


def air_conditioner_menu(system):
    while True:
        system.update()
        print("\n" + "-" * 40)
        print("   AIR CONDITIONER MENU")
        print("-" * 40)
        print(f"Home Ambient Temperature: {system.getAmbientTemp()} °C")
        print(f"Home Desired Temperature: {system.getDesiredTemp()} °C")
        print(f"Fan Speed: {system.getFanSpeed()} rps")
        print(f"Connection Port: COM10")
        print(f"Connection Baudrate: 9600")
        print("-" * 40)
        print("1. Enter the desired temperature")
        print("2. Return")

        choice = input("Seçim: ")
        if choice == '1':
            try:
                val = float(input("Enter Desired Temp: "))
                system.setDesiredTemp(val)
            except ValueError:
                print("Hata: Sayı giriniz.")
        elif choice == '2':
            break
        time.sleep(0.5)


def curtain_control_menu(system):
    while True:
        system.update()
        print("\n" + "-" * 40)
        print("   CURTAIN CONTROL MENU")
        print("-" * 40)
        print(f"Outdoor Temperature: {system.getOutdoorTemp()} °C")
        print(f"Outdoor Pressure: {system.getOutdoorPress()} hPa")
        print(f"Curtain Status: {system.curtainStatus} %")
        print(f"Light Intensity: {system.getLightIntensity()} Lux")
        print(f"Connection Port: COM11")
        print(f"Connection Baudrate: 9600")
        print("-" * 40)
        print("1. Enter the desired curtain status")
        print("2. Return")

        choice = input("Seçim: ")
        if choice == '1':
            try:
                val = float(input("Enter Desired Curtain % (0-100): "))
                if 0 <= val <= 100:
                    system.setCurtainStatus(val)
                else:
                    print("0-100 arası giriniz.")
            except ValueError:
                print("Hata: Sayı giriniz.")
        elif choice == '2':
            break
        time.sleep(0.5)


if __name__ == "__main__":
    main_menu()