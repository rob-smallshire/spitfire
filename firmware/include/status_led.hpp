#ifndef SPITFIRE_STATUS_LED_HPP
#define SPITFIRE_STATUS_LED_HPP

/// Status LED on PD7 (active-high on Rev 1 PCB: PD7 -> R2 -> D2 -> GND).
///
/// Provides a startup indication and a once-per-second heartbeat (two brief
/// flashes) driven by a Timer0 compare interrupt, independent of whatever
/// the main loop is doing. Timer0 is reserved for this module.
namespace status_led {

/// Configure PD7 as an output with the LED off.
void init();

/// Three quick flashes (blocking, ~240 ms) to indicate a reset.
void startup_flash();

/// Start the Timer0-driven heartbeat. The caller must enable interrupts.
void start_heartbeat();

}  // namespace status_led

#endif  // SPITFIRE_STATUS_LED_HPP
