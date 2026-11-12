#ifndef RUNNER_WINDOWS_TRUST_STORE_H_
#define RUNNER_WINDOWS_TRUST_STORE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateWindowsTrustStoreChannel(flutter::BinaryMessenger* messenger);

#endif
