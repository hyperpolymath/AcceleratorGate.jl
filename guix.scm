; SPDX-License-Identifier: MPL-2.0
;; guix.scm — GNU Guix package definition for AcceleratorGate.jl
;; Usage: guix shell -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses))

(package
  (name "AcceleratorGate.jl")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (synopsis "AcceleratorGate.jl")
  (description "AcceleratorGate.jl — part of the hyperpolymath ecosystem.")
  (home-page "https://github.com/hyperpolymath/AcceleratorGate.jl")
  (license ((@@ (guix licenses) license) "MPL-2.0"
             "https://www.mozilla.org/MPL/2.0/")))
