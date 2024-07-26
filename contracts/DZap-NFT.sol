// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/// @custom:security-contact mujahidshaik2002@gmail.com
contract MyDZapNfts is ERC721Enumerable {
    uint256 private s_dZapId;

    constructor() ERC721("DZapNFT", "DZT"){
        s_dZapId = 10;
        for (uint256 i = 0; i < 10; ++i) {
            _safeMint(msg.sender, i);
        }
    }

    function mintDZapNft(address to) public {
        uint256 tokenId=getDZapId();
        s_dZapId+=1;
        _safeMint(to, tokenId);
    }

    function getDZapId() public view returns (uint256) {
        return s_dZapId;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "";
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
