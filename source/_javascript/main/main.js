(function(){
    
    // defend against Comcast injection
    var head = document.getElementsByTagName('head')[0],
        children = head.children,
        total_children = children.length,
        child = null,
        i = 0,
        tag,
        elements, e_len, element,
        el_extration_re = /(#[^\s{;]+) /g;
    
    while ( i < total_children ) {
        
        // get the element
        child = children[i];
        tag = child.nodeName.toLowerCase();
        
        // if we hit the title or meta, most likely we have skipped over the injection
        if ( tag == 'title' || tag == 'meta' ) {
            break;
        }
        
        if ( tag == 'style' ) {
            // jackpot: this is our map to the injected crappola
            elements = child.innerText.match( el_extration_re );
            e_len = elements.length;
            
            while ( --e_len )
            {
                // find the element
                element = document.getElementById( elements[e_len].replace( '#', '' ) );
                
                // if it exists, remove it
                if ( element )
                {
                    //console.log( 'found crap! ' + elements[e_len] );
                    element.parentNode.removeChild( element );
                }
            }
        }
        
    }

    element = null;
    child = null;
    head = null;
    
}());