terraform {
  cloud {
    organization = "Moonswitch"

    workspaces {
      tags = ["lambda"]
    }
  }
}
