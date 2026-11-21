"use client";

/// The middle of every pay screen (plan §5.2): who the money goes to, the
/// four things a banking app asks for — each on its own large line with a
/// Copy button — and a three-step guide for somebody who has never added a
/// payee before.
///
/// Shared by the public pay page (`/p/<token>`) and the signed-in pay screen
/// (`/clubs/<id>/pay`), so a player sees the same thing whichever way in.
/// Nothing here is ever logged or put in a URL: it holds a full account number.

import { useEffect, useState } from "react";
import { money } from "@/lib/api";
import { checker, paidBefore, payeeLine, shortDate, type BankDetails } from "@/lib/payments";
import { firstName } from "@/lib/pay-link";
import { copyText } from "@/lib/clipboard";
import { CopyButton } from "@/components/CopyButton";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

export function PayDetails({
  account,
  reference,
  amountCents,
  currency,
  headingLevel = 2,
}: {
  account: BankDetails;
  reference: string;
  /// What to pay, for the guide's last step.
  amountCents: number;
  currency: string;
  headingLevel?: 2 | 3;
}) {
  const t = useT();
  // Read after mounting: storage is not there on the server, and the server's
  // HTML must match the first render.
  const [before, setBefore] = useState(false);
  useEffect(() => setBefore(paidBefore(account)), [account]);

  const Heading = headingLevel === 2 ? "h2" : "h3";
  const first = firstName(account.holder_name);
  const amount = money(amountCents, currency);

  return (
    <div className="pay-to">
      <Heading className="pay-payee">{payeeLine(account, t)}</Heading>
      {account.is_personal && <p className="pay-own">{t("pw2.own_account", { first })}</p>}
      {account.changed_at && (
        <p className="pay-warn" role="note">
          {t("pay.details_changed_on", { date: shortDate(account.changed_at) })}
        </p>
      )}

      <dl className="pay-details pay-rows">
        <PayeeRows account={account} />
        <PayRow term={t("pw2.row_reference")} value={reference} what={t("pw2.what_reference")} />
      </dl>

      {before && <p className="pay-usual">{t("pw2.pay_as_usual", { name: checker(account) ?? account.holder_name })}</p>}
      <details className="pay-guide">
        <summary>{t("pw2.first_time")}</summary>
        <ol>
          <li>
            <span className="pay-guide-pic" aria-hidden="true">
              <Icon name="lock" size={26} />
            </span>
            <span>{t("pw2.step_open_app")}</span>
          </li>
          <li>
            <span className="pay-guide-pic" aria-hidden="true">
              <Icon name="plus" size={26} />
            </span>
            <span>{t("pw2.step_new_payee")}</span>
          </li>
          <li>
            <span className="pay-guide-pic" aria-hidden="true">
              <Icon name="copy" size={26} />
            </span>
            <span>{t("pw2.step_pay_and_paste", { amount, reference })}</span>
          </li>
        </ol>
      </details>
    </div>
  );
}

/// Who to pay: the name, sort code and account number, each with Copy. Shared
/// with the standing-order card, which needs the same three.
export function PayeeRows({ account }: { account: BankDetails }) {
  const t = useT();
  return (
    <>
      <PayRow term={t("pw2.row_name")} value={account.holder_name} what={t("pw2.what_name")} />
      {/* Copied as six digits: some banking apps take nothing else in a
          six-character box, and "40-11-22" would arrive as "40-11-". */}
      <PayRow
        term={t("pay.sort_code")}
        value={account.sort_code}
        copy={account.sort_code.replace(/\D/g, "")}
        what={t("pw2.what_sort_code")}
      />
      <PayRow term={t("pay.account_number")} value={account.account_number} what={t("pw2.what_account_number")} />
    </>
  );
}

/// One line: what it is, the value, and its Copy button.
export function PayRow({ term, value, what, copy }: { term: string; value: string; what: string; copy?: string }) {
  return (
    <div className="pay-detail">
      <dt>{term}</dt>
      <dd>
        <span className="pay-value">{value}</span>
        <CopyButton text={copy ?? value} what={what} className="btn pay-copy" />
      </dd>
    </div>
  );
}

/// "Send these details to someone" — the son or daughter who does the
/// banking. Through the phone's share sheet where there is one, and the
/// clipboard otherwise. Never as a link: a URL is the wrong place for an
/// account number.
export function SendDetails({
  account,
  reference,
  amountCents,
  currency,
  title,
}: {
  account: BankDetails;
  reference: string;
  amountCents: number;
  currency: string;
  title: string;
}) {
  const t = useT();
  const text = [
    t("pw2.send_details_line", { amount: money(amountCents, currency), title }),
    `${t("pw2.row_name")}: ${account.holder_name}`,
    `${t("pay.sort_code")}: ${account.sort_code}`,
    `${t("pay.account_number")}: ${account.account_number}`,
    `${t("pay.reference")}: ${reference}`,
  ].join("\n");
  return (
    <SendText
      title={t("pw2.send_details")}
      help={t("pw2.send_details_help")}
      button={t("pw2.send_details_button")}
      text={text}
    />
  );
}

/// A block of text for somebody else to act on, sent from the phone's share
/// sheet, or copied where there is none.
export function SendText({ title, help, button, text }: { title: string; help: string; button: string; text: string }) {
  const t = useT();
  const [canShare, setCanShare] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  useEffect(() => setCanShare(typeof navigator !== "undefined" && typeof navigator.share === "function"), []);

  const share = async () => {
    setSaid(null);
    try {
      await navigator.share({ text });
    } catch (e) {
      // Closing the sheet is not a failure. Anything else falls back to copying.
      if ((e as { name?: string }).name === "AbortError") return;
      setSaid((await copyText(text)) ? t("pw2.details_copied") : t("pay.copy_failed"));
    }
  };

  return (
    <div className="pay-send">
      <h3 className="pay-send-title">{title}</h3>
      <p className="muted">{help}</p>
      {canShare ? (
        <button className="btn" type="button" onClick={() => void share()}>
          <Icon name="share" size={18} /> {button}
        </button>
      ) : (
        <CopyButton text={text} what={t("pay.all_the_details")} label={t("pw2.copy_all_details")} />
      )}
      {said && (
        <p className="subtle" role="status">
          {said}
        </p>
      )}
    </div>
  );
}
