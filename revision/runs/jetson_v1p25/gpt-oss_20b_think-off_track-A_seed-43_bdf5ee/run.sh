#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

is_outdated() {
    local out=$1; shift
    for in in "$@"; do
        if [ "$in" -nt "$out" ]; then
            return 0
        fi
    done
    return 1
}

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai

    if [ ! -f "$bai" ] || is_outdated "$bai" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz; then
        bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ $THREADS -o "$bam"
    fi

    if [ ! -f "$bai" ] || is_outdated "$bai" "$bam"; then
        samtools index -@ $THREADS "$bam"
    fi

    vcf=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    if [ ! -f "$tbi" ] || is_outdated "$tbi" "$bam"; then
        tmp_vcf=results/${sample}.vcf
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$tmp_vcf" "$bam"
        bgzip -c "$tmp_vcf" > "${tmp_vcf}.gz"
        mv "${tmp_vcf}.gz" "$vcf"
        tabix -p vcf "$vcf"
        rm "$tmp_vcf"
    fi
done

collapsed=results/collapsed.tsv
needs_collapse=false
for sample in "${SAMPLES[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if [ ! -f "$collapsed" ] || is_outdated "$collapsed" "$vcf_gz"; then
        needs_collapse=true
        break
    fi
done

if $needs_collapse; then
    tmpfile=results/collapsed.tmp.$$
    cat > "$tmpfile" <<'EOF'
sample	chrom	pos	ref	alt	af
EOF
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmpfile"
    done
    mv "$tmpfile" "$collapsed"
fi

exit 0