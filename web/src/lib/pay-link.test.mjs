// `npm test` from web/ — the pay link's pure helpers.

import assert from "node:assert/strict";
import { test } from "node:test";

import { firstName, fingerprint, fitWithin, isPayLinkPath, isProfileToken, surnameRef, whatsappUrl } from "./pay-link.ts";

test("a profile token is 24 letters and digits; a pay link is anything else", () => {
  assert.equal(isProfileToken("ProfileTokenForTests0000"), true);
  assert.equal(isProfileToken("PayLinkTokenForTestsOnly-0000000000000"), false);
  // A pay link with a character changed or cut off is still a pay link, so it
  // reaches the friendly wrong-link page and not a sign-in screen.
  assert.equal(isProfileToken("PayLinkTokenForTestsOnly-000000000000X"), false);
  assert.equal(isProfileToken("PayLinkTokenForT"), false);
});

test("only /p/<pay token> is a public pay page", () => {
  assert.equal(isPayLinkPath("/p/PayLinkTokenForTestsOnly-0000000000000"), true);
  assert.equal(isPayLinkPath("/p/ProfileTokenForTests0000"), false);
  assert.equal(isPayLinkPath("/profile"), false);
  assert.equal(isPayLinkPath("/players/p/x"), false);
  assert.equal(isPayLinkPath("/p/%E0%A4%A"), true);
  assert.equal(isPayLinkPath("/pay/PayLinkTokenForTestsOnly-0000000000000"), true);
  assert.equal(isPayLinkPath("/pay/ProfileTokenForTests0000"), true);
  assert.equal(isPayLinkPath("/pay/"), false);
});

test("a picture is sized down to fit, never up, keeping its shape", () => {
  assert.deepEqual(fitWithin(3024, 4032, 1600), { width: 1200, height: 1600 });
  assert.deepEqual(fitWithin(4032, 3024, 1600), { width: 1600, height: 1200 });
  assert.deepEqual(fitWithin(800, 600, 1600), { width: 800, height: 600 });
  assert.deepEqual(fitWithin(0, 0, 1600), { width: 1, height: 1 });
});

test("WhatsApp gets the message as text, encoded", () => {
  assert.equal(whatsappUrl("Nets: £5 each.\nTap to pay"), "https://wa.me/?text=Nets%3A%20%C2%A35%20each.%0ATap%20to%20pay");
});

test("the paid-before fingerprint is stable and changes with the details", () => {
  assert.equal(fingerprint("Aman Gill|40-11-22|12345678"), fingerprint("Aman Gill|40-11-22|12345678"));
  assert.notEqual(fingerprint("Aman Gill|40-11-22|12345678"), fingerprint("Aman Gill|40-11-22|12345679"));
  assert.match(fingerprint(""), /^[0-9a-f]{8}$/);
});

test("names", () => {
  assert.equal(firstName("  Aman Gill "), "Aman");
  assert.equal(surnameRef("Ravi Sharma"), "SHARMA");
  assert.equal(surnameRef("Cher"), "CHER");
});
