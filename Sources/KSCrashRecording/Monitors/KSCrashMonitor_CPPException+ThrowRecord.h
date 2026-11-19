// SPDX-License-Identifier: MIT
#ifndef KSCrashMonitor_CPPException_ThrowRecord_h
#define KSCrashMonitor_CPPException_ThrowRecord_h

#include <atomic>

#include "KSCxaThrowSwapper.h"
#include "KSStackCursor.h"

namespace
{

// We use the exception's address to identify its saved throw stack, without increasing its reference count.
// When libc++abi destroys the exception, our destructor callback clears the slot before that address can
// be reused for another exception, even if destruction happens on a different thread.
class ThrowRecord
{
   public:
    KSStackCursor cursor {};

    bool tryReserve()
    {
        void *expected = nullptr;
        // The slot itself is a sentinel: it can never be a live exception's address.
        return owner.compare_exchange_strong(expected, this, std::memory_order_acq_rel);
    }

    void publish(void *object, ksct_destructor destructor)
    {
        destroy = destructor;
        owner.store(object, std::memory_order_release);
    }

    // The caller must keep the primary exception alive while reading its cursor.
    bool matches(void *object) const { return owner.load(std::memory_order_acquire) == object; }

    void release(void *object)
    {
        // Synchronize with publication even when the final exception_ptr died on another thread.
        (void)owner.load(std::memory_order_acquire);
        auto originalDestructor = destroy;
        owner.store(nullptr, std::memory_order_release);

        if (originalDestructor != nullptr) {
            originalDestructor(object);
        }
    }

   private:
    std::atomic<void *> owner { nullptr };
    ksct_destructor destroy = nullptr;
};

}  // namespace

#endif
