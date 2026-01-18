export const PACKAGE_ID = "0x4f4f8dccf36e42e7147c3616f50a43f2011cf8420c46507c7571b4020bcb73a2";
export const MODULE_NAME = "multisigv2";

export const WALLET_TYPE_PLURALITY = 0;
export const WALLET_TYPE_UNANIMITY = 1;

export const STATUS_PENDING = 0;
export const STATUS_EXECUTED = 1;
export const STATUS_REJECTED = 2;
export const STATUS_EXPIRED = 3;

export const ACTION_SEND_SUI = 0;
export const ACTION_ADD_OWNER = 1;
export const ACTION_REMOVE_OWNER = 2;

export const STATUS_LABELS = {
  [STATUS_PENDING]: "On-going",
  [STATUS_EXECUTED]: "Approved",
  [STATUS_REJECTED]: "Rejected",
  [STATUS_EXPIRED]: "Expired",
};

export const ACTION_LABELS = {
  [ACTION_SEND_SUI]: "Send SUI",
  [ACTION_ADD_OWNER]: "Add Owner",
  [ACTION_REMOVE_OWNER]: "Remove Owner",
};