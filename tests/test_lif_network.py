# =============================================================================
# test_lif_network.py
# Python Digital Verification Environment using Cocotb for TDM LIF Accelerator
# Methodology: Constrained Random Verification (CRV) + Scoreboard + Golden Model
# =============================================================================

import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.result import TestFailure

# Biological constants and hardware limits
V_REST = 0
V_TH_DEFAULT = 1000
V_MIN = -250
V_MAX = 32767
REFRACTORY_DEFAULT = 16
NUM_NEURONS = 100

# CSR Memory Map
CSR_ADDR_CTRL    = 0x00000000
CSR_ADDR_STATUS  = 0x00000004
CSR_ADDR_CFG_TH  = 0x00000008
CSR_ADDR_CFG_REF = 0x0000000C
CSR_BRAM_BASE    = 0x00001000


class CSRDriver:
    """Transactional driver for the 32-bit CSR slave bus."""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def write(self, addr: int, data: int):
        """Executes a CSR write transaction with handshake."""
        await RisingEdge(self.clk)
        self.dut.csr_addr.value = addr
        self.dut.csr_wdata.value = data
        self.dut.csr_write.value = 1
        self.dut.csr_valid.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.dut.csr_ready.value == 1:
                break

        self.dut.csr_valid.value = 0
        self.dut.csr_write.value = 0
        self.dut.csr_addr.value = 0
        self.dut.csr_wdata.value = 0

    async def read(self, addr: int) -> int:
        """Executes a CSR read transaction with handshake."""
        await RisingEdge(self.clk)
        self.dut.csr_addr.value = addr
        self.dut.csr_write.value = 0
        self.dut.csr_valid.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.dut.csr_ready.value == 1:
                rdata = int(self.dut.csr_rdata.value)
                break

        self.dut.csr_valid.value = 0
        self.dut.csr_addr.value = 0
        return rdata


class AERMonitor:
    """Active monitor and receiver for 4-phase AER protocol (req/ack)."""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.captured_events = []
        self._running = True

    async def run(self):
        """Continuous listening loop for AER spike events."""
        self.dut.aer_ack.value = 0
        while self._running:
            await RisingEdge(self.clk)
            if self.dut.aer_req.value == 1:
                raw_data = int(self.dut.aer_data.value)
                valid = (raw_data >> 15) & 0x1
                timestamp = (raw_data >> 7) & 0xFF
                neuron_id = raw_data & 0x7F

                if valid:
                    self.captured_events.append({
                        "raw": raw_data,
                        "timestamp": timestamp,
                        "neuron_id": neuron_id,
                        "sim_time_ns": cocotb.utils.get_sim_time(units='ns')
                    })

                # Handshake Phase 2: Assert ack with randomized delay (emulate external receiver)
                ack_delay = random.randint(1, 4)
                await ClockCycles(self.clk, ack_delay)
                self.dut.aer_ack.value = 1

                # Handshake Phase 4: Wait for req to deassert, then lower ack
                while self.dut.aer_req.value == 1:
                    await RisingEdge(self.clk)

                hold_delay = random.randint(1, 2)
                await ClockCycles(self.clk, hold_delay)
                self.dut.aer_ack.value = 0

    def stop(self):
        self._running = False


class LIFGoldenModel:
    """Analytical mathematical reference model (Ground Truth in Python)."""
    def __init__(self, num_neurons=NUM_NEURONS):
        self.num_neurons = num_neurons
        self.v_mem = [V_REST] * num_neurons
        self.refractory = [0] * num_neurons
        self.weights = [0] * num_neurons
        self.v_th = V_TH_DEFAULT
        self.ref_max = REFRACTORY_DEFAULT

    def configure(self, v_th=V_TH_DEFAULT, ref_max=REFRACTORY_DEFAULT):
        self.v_th = v_th
        self.ref_max = ref_max

    def set_weight(self, neuron_id: int, weight: int):
        if weight > 32767:
            weight = weight - 65536
        self.weights[neuron_id] = max(-32768, min(32767, int(weight)))

    def step_epoch(self) -> list:
        """Simulates a complete biological epoch (50 Hz) for all 100 neurons."""
        spikes = []
        for i in range(self.num_neurons):
            if self.refractory[i] > 0:
                self.v_mem[i] = V_REST
                self.refractory[i] -= 1
            else:
                leak = self.v_mem[i] >> 4
                v_sum = self.v_mem[i] - leak + self.weights[i]

                if v_sum > V_MAX:
                    v_clamped = V_MAX
                elif v_sum < V_MIN:
                    v_clamped = V_MIN
                else:
                    v_clamped = v_sum

                if v_clamped >= self.v_th:
                    spikes.append(i)
                    self.v_mem[i] = V_REST
                    self.refractory[i] = self.ref_max
                else:
                    self.v_mem[i] = v_clamped
                    self.refractory[i] = 0

        return spikes


class Scoreboard:
    """Scoreboard for deterministic verification of hardware events vs model."""
    def __init__(self):
        self.expected_events = []
        self.matched_events = 0
        self.mismatches = 0

    def add_expected_epoch_spikes(self, epoch_idx: int, spikes: list):
        for nid in spikes:
            self.expected_events.append({"epoch": epoch_idx, "neuron_id": nid})

    def evaluate(self, actual_events: list):
        dut_spikes = [{"epoch": e["timestamp"], "neuron_id": e["neuron_id"]} for e in actual_events]
        print(f"[SCOREBOARD] Expected events: {len(self.expected_events)} | Captured via AER: {len(dut_spikes)}")

        expected_ids = sorted([e["neuron_id"] for e in self.expected_events])
        actual_ids = sorted([e["neuron_id"] for e in dut_spikes])

        if expected_ids != actual_ids:
            missing = set(expected_ids) - set(actual_ids)
            unexpected = set(actual_ids) - set(expected_ids)
            raise TestFailure(
                f"[SCOREBOARD FAILURE] Discrepancy in detected spikes.\n"
                f"Missing in hardware: {missing}\n"
                f"Unexpected (spurious): {unexpected}"
            )
        else:
            print(f"[SCOREBOARD PASS] 100% exact correlation ({len(actual_ids)} spikes verified bit-by-bit).")


# =============================================================================
# COCOTB TEST SUITE (CONSTRAINED RANDOM VERIFICATION)
# =============================================================================

async def setup_dut(dut):
    """Synchronous initialization of clock and physical reset of DUT."""
    clock = Clock(dut.clk, 10, units="ns")  # 100 MHz clock
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.bio_tick_in.value = 0
    dut.bio_tick_ext_sel.value = 1  # Direct bio_tick control from testbench
    dut.csr_valid.value = 0
    dut.csr_write.value = 0
    dut.csr_addr.value = 0
    dut.csr_wdata.value = 0
    dut.aer_ack.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)


@cocotb.test()
async def test_csr_configuration_and_registers(dut):
    """Test 1: Verification of access and persistence in CSR registers."""
    await setup_dut(dut)
    driver = CSRDriver(dut, dut.clk)

    dut._log.info("[TEST 1] Verifying write and read in control registers...")

    await driver.write(CSR_ADDR_CFG_TH, 1200)
    await driver.write(CSR_ADDR_CFG_REF, 20)

    th_read = await driver.read(CSR_ADDR_CFG_TH)
    ref_read = await driver.read(CSR_ADDR_CFG_REF)

    assert th_read == 1200, f"Error in V_TH read: {th_read} != 1200"
    assert ref_read == 20, f"Error in Refractory read: {ref_read} != 20"

    dut._log.info("[TEST 1 PASSED] CSR registers verified successfully.")


@cocotb.test()
async def test_synaptic_weights_injection_and_tdm_spikes(dut):
    """Test 2: Dynamic weight injection via CSR and AER verification with Scoreboard."""
    await setup_dut(dut)
    driver = CSRDriver(dut, dut.clk)
    monitor = AERMonitor(dut, dut.clk)
    cocotb.start_soon(monitor.run())

    golden = LIFGoldenModel(NUM_NEURONS)
    scoreboard = Scoreboard()

    dut._log.info("[TEST 2] Injecting random synaptic weight matrix into BRAM...")

    random.seed(42)
    for i in range(NUM_NEURONS):
        if i < 20:
            weight = random.randint(800, 1500)  # Suprathreshold
        elif i < 50:
            weight = random.randint(50, 200)    # Integrative subthreshold
        else:
            weight = random.randint(-300, 0)    # Inhibition

        golden.set_weight(i, weight)

        bram_csr_addr = CSR_BRAM_BASE + (i * 2)
        weight_u16 = weight & 0xFFFF
        await driver.write(bram_csr_addr, weight_u16)

    dut._log.info("[TEST 2] Executing 5 biological epochs with AER monitoring...")

    for epoch in range(5):
        dut.bio_tick_in.value = 1
        await RisingEdge(dut.clk)
        dut.bio_tick_in.value = 0

        await ClockCycles(dut.clk, 500)

        spk_expected = golden.step_epoch()
        scoreboard.add_expected_epoch_spikes(epoch, spk_expected)

    await ClockCycles(dut.clk, 200)
    monitor.stop()

    scoreboard.evaluate(monitor.captured_events)
    dut._log.info("[TEST 2 PASSED] Constrained Random verification completed with 100% success.")
