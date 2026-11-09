import numpy as np
import pandas as pd

# we don't have medical ethics board approval to induce heatstroke or hypoxia in real people,
# so i built this state-space biological simulator, instead of using basic random numbers 
# (which just trains a glorified if-else model), this uses exponential moving averages 
# to simulate real thermal inertia, heart rate lag, and max30102 optical motion noise.

SAMPLE_RATE_HZ = 10
SAMPLES_PER_DEMOGRAPHIC = 30000 # 50 mins of continuous 10hz telemetry per demographic

# baseline targets for a normal adult. 
# note: accel is in m/s2 (9.81 = 1g resting) to match our c++ mpu6050 register math.
BASE_TARGETS = {
    "NOMINAL":              {"hr": 72,  "spo2": 98.0, "gsr": 1600, "skin_t": 33.2, "accel": 9.81, "amb_t": 25.0, "hum": 45.0, "voc": 45.0},
    "PHYSICAL_EXERTION":    {"hr": 142, "spo2": 96.5, "gsr": 2900, "skin_t": 35.4, "accel": 16.5, "amb_t": 27.0, "hum": 52.0, "voc": 40.0},
    "HEAT_STRAIN":          {"hr": 134, "spo2": 95.0, "gsr": 3750, "skin_t": 38.2, "accel": 10.2, "amb_t": 41.5, "hum": 78.0, "voc": 32.0},
    "RESPIRATORY_DISTRESS": {"hr": 118, "spo2": 87.5, "gsr": 2300, "skin_t": 32.8, "accel": 9.50, "amb_t": 29.0, "hum": 62.0, "voc": 8.5},
    "FALL_IMPACT":          {"hr": 155, "spo2": 95.5, "gsr": 3100, "skin_t": 34.0, "accel": 9.81, "amb_t": 26.0, "hum": 48.0, "voc": 42.0}
}

# biological offsets for our 3 target user profiles.
# elderly users have lower max heart rates and slightly lower baseline spo2.
# industrial workers (miners/factory) work in hotter environments with higher baseline sweat (gsr).
DEMOGRAPHICS = {
    "standard":   {"hr_scale": 1.00, "spo2_offset": 0.0,  "gsr_offset": 0,    "skin_t_offset": 0.0},
    "elderly":    {"hr_scale": 0.85, "spo2_offset": -2.0, "gsr_offset": -300, "skin_t_offset": -0.4},
    "industrial": {"hr_scale": 1.08, "spo2_offset": -0.5, "gsr_offset": 650,  "skin_t_offset": 0.6}
}

class PhysiologicalTwin:
    def __init__(self, mod):
        self.mod = mod
        # start the simulation at a normal resting state
        self.hr = 72.0 * mod["hr_scale"]
        self.spo2 = 98.0 + mod["spo2_offset"]
        self.gsr = 1600.0 + mod["gsr_offset"]
        self.skin_t = 33.2 + mod["skin_t_offset"]
        self.amb_t = 25.0
        self.hum = 45.0
        self.voc = 45.0
        self.accel = 9.81

    def step(self, state, is_falling=False, fall_tick=0):
        t = BASE_TARGETS[state]
        
        target_hr = t["hr"] * self.mod["hr_scale"]
        target_spo2 = t["spo2"] + self.mod["spo2_offset"]
        target_gsr = t["gsr"] + self.mod["gsr_offset"]
        target_skin_t = t["skin_t"] + self.mod["skin_t_offset"]

        # applying exponential moving averages so values ramp up and cool down naturally.
        # heart rate reacts fairly quick (alpha=0.04), skin temp takes way longer (alpha=0.008).
        self.hr += (target_hr - self.hr) * 0.04 + np.random.normal(0, 0.6)
        self.spo2 += (target_spo2 - self.spo2) * 0.08 + np.random.normal(0, 0.15)
        self.gsr += (target_gsr - self.gsr) * 0.03 + np.random.normal(0, 12.0)
        self.skin_t += (target_skin_t - self.skin_t) * 0.008 + np.random.normal(0, 0.03)
        
        # bme680 sits close to the esp32-s3 on the breadboard so it picks up ~1.8c of pcb heat creep
        self.amb_t += ((t["amb_t"] + 1.8) - self.amb_t) * 0.01 + np.random.normal(0, 0.08)
        self.hum += (t["hum"] - self.hum) * 0.01 + np.random.normal(0, 0.3)
        self.voc += (t["voc"] - self.voc) * 0.05 + np.random.normal(0, 0.4)

        if not is_falling:
            # add natural wrist movement jitter around the target acceleration
            accel_jitter = 2.8 if state == "PHYSICAL_EXERTION" else 0.45
            self.accel = np.clip(t["accel"] + np.random.normal(0, accel_jitter), 4.0, 19.5)

        hr_out = self.hr
        spo2_out = self.spo2

        # simulating max30102 optical motion artifacts:
        # when acceleration is high (>13.5 m/s2), the sensor shifts on the wrist and corrupts the ppg reading
        if self.accel > 13.5:
            motion_factor = (self.accel - 13.5) * 0.4
            hr_out += np.random.normal(0, 2.5 * motion_factor)
            spo2_out -= np.abs(np.random.normal(0, 0.6 * motion_factor))

        # 0.4% chance of an ectopic heartbeat spike or optical dropout so the model learns to ignore single-tick outliers
        if np.random.rand() < 0.004:
            hr_out += np.random.choice([-12.0, 18.0])

        # adding 50hz powerline hum and skin contact drift to the raw gsr adc pin
        gsr_out = self.gsr + np.sin(np.random.rand() * 2 * np.pi) * 20.0

        # fall sequence physics: brief weightlessness (<3 m/s2) -> hard impact (>22 m/s2) -> lying still (~9.8 m/s2)
        if is_falling:
            if fall_tick in [0, 1]:
                self.accel = np.random.uniform(1.2, 2.8) # freefall phase
            elif fall_tick in [2, 3, 4]:
                self.accel = np.random.uniform(22.5, 31.0) # hitting the ground
            else:
                self.accel = np.random.normal(9.81, 0.15) # lying motionless after impact
                self.hr += 0.8 # adrenaline spike post-fall

        return [
            round(np.clip(hr_out, 35.0, 210.0), 1),
            round(np.clip(spo2_out, 65.0, 100.0), 1),
            int(np.clip(gsr_out, 100, 4095)),
            round(np.clip(self.skin_t, 24.0, 42.0), 2),
            round(np.clip(self.accel, 0.5, 35.0), 2),
            round(np.clip(self.amb_t, 10.0, 55.0), 2),
            round(np.clip(self.hum, 10.0, 100.0), 1),
            round(np.clip(self.voc, 1.0, 200.0), 1),
            state
        ]

def build_dataset_for_profile(profile_name, mod):
    print(f"generating continuous markov timeline for [{profile_name}] profile...")
    twin = PhysiologicalTwin(mod)
    rows = []

    continuous_states = ["NOMINAL", "PHYSICAL_EXERTION", "HEAT_STRAIN", "RESPIRATORY_DISTRESS"]
    current_state = "NOMINAL"
    ticks_in_state = 0
    target_duration = np.random.randint(400, 1200) # hold each physiological state for 40 to 120 seconds

    fall_active = False
    fall_tick = 0

    for _ in range(SAMPLES_PER_DEMOGRAPHIC):
        if fall_active:
            rows.append(twin.step("FALL_IMPACT", is_falling=True, fall_tick=fall_tick))
            fall_tick += 1
            if fall_tick >= 60: # 6 seconds per fall event
                fall_active = False
                current_state = "NOMINAL"
                ticks_in_state = 0
        else:
            rows.append(twin.step(current_state))
            ticks_in_state += 1

            if ticks_in_state >= target_duration:
                # 12% chance of triggering a fall event between transitions so we get plenty of fall samples
                if np.random.rand() < 0.12:
                    fall_active = True
                    fall_tick = 0
                else:
                    current_state = np.random.choice(continuous_states, p=[0.30, 0.25, 0.25, 0.20])
                    target_duration = np.random.randint(400, 1200)
                    ticks_in_state = 0

    cols = ["hr_bpm", "spo2_pct", "gsr_raw", "skin_temp_c", "accel_g", "amb_temp_c", "humidity_pct", "voc_gas_kohm", "label"]
    df = pd.DataFrame(rows, columns=cols)

    # save an unshuffled slice of the standard dataset so we can plot the continuous time-series curves in colab
    if profile_name == "standard":
        df.iloc[:2000].to_csv("qyra_sequential_preview.csv", index=False)

    # shuffle the training rows so the dense network learns sensor correlations instead of memorizing time order
    df_shuffled = df.sample(frac=1, random_state=42).reset_index(drop=True)
    filename = f"qyra_data_{profile_name}.csv"
    df_shuffled.to_csv(filename, index=False)
    print(f" -> saved {filename} ({len(df_shuffled)} rows) | class counts: {df_shuffled['label'].value_counts().to_dict()}")

if __name__ == "__main__":
    for name, modifiers in DEMOGRAPHICS.items():
        build_dataset_for_profile(name, modifiers)
    print("\nall 3 demographic datasets generated.")
